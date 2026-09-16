using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Clawdmeter.Activity;
using Clawdmeter.Usage;

namespace Clawdmeter.Platform;

/// Turns an old phone into a little usage screen. The PC answers a page on the home
/// network, the phone keeps it open, and nothing leaves the network. Off until you turn
/// it on, and every request needs the key from the address.
public sealed class MiniDisplay : IDisposable
{
    public const int Port = 47848;

    private readonly UsageStore store;
    private readonly ClaudeActivityWatcher watcher;
    private TcpListener? listener;
    private CancellationTokenSource? life;
    private readonly object gate = new();

    public MiniDisplay(UsageStore store, ClaudeActivityWatcher watcher)
    {
        this.store = store;
        this.watcher = watcher;
        Settings.Changed += Follow;
    }

    public void Start() => Follow();

    /// The address to type on the phone, or null when the screen is off.
    public string? Address
    {
        get
        {
            if (!Settings.Current.MiniDisplay) return null;
            var host = LocalAddress() ?? "127.0.0.1";
            return $"http://{host}:{Port}/?k={Key()}";
        }
    }

    private void Follow()
    {
        lock (gate)
        {
            var wanted = Settings.Current.MiniDisplay;
            if (wanted == (listener is not null)) return;
            if (wanted) Open(); else Close();
        }
    }

    private void Open()
    {
        try
        {
            listener = new TcpListener(IPAddress.Any, Port);
            listener.Start();
            life = new CancellationTokenSource();
            _ = Task.Run(() => Serve(listener, life.Token));
        }
        catch (SocketException)
        {
            // Another app already holds the port, or the firewall said no.
            listener = null;
        }
    }

    private void Close()
    {
        life?.Cancel();
        life?.Dispose();
        life = null;
        try
        {
            listener?.Stop();
        }
        catch (SocketException)
        {
        }
        listener = null;
    }

    private async Task Serve(TcpListener server, CancellationToken cancel)
    {
        while (!cancel.IsCancellationRequested)
        {
            TcpClient client;
            try
            {
                client = await server.AcceptTcpClientAsync(cancel).ConfigureAwait(false);
            }
            catch (Exception exception) when (exception is OperationCanceledException or SocketException or ObjectDisposedException)
            {
                return;
            }
            _ = Task.Run(() => Answer(client), CancellationToken.None);
        }
    }

    private async Task Answer(TcpClient client)
    {
        using (client)
        {
            try
            {
                client.ReceiveTimeout = 5000;
                client.SendTimeout = 5000;
                if (client.Client.RemoteEndPoint is not IPEndPoint remote || !IsHomeNetwork(remote.Address))
                {
                    return;
                }

                using var stream = client.GetStream();
                var request = await ReadRequest(stream).ConfigureAwait(false);
                if (request is null) return;

                var (method, path, query) = request.Value;
                if (method != "GET")
                {
                    await Write(stream, 405, "text/plain", "Only GET is served here."u8.ToArray()).ConfigureAwait(false);
                    return;
                }
                if (!Matches(query, Key()))
                {
                    await Write(stream, 401, "text/plain", "The key in the address does not match."u8.ToArray()).ConfigureAwait(false);
                    return;
                }

                switch (path)
                {
                    case "/":
                    case "/index.html":
                        await Write(stream, 200, "text/html; charset=utf-8", Encoding.UTF8.GetBytes(MiniPage.Html)).ConfigureAwait(false);
                        break;
                    case "/usage":
                        await Write(stream, 200, "application/json; charset=utf-8", Encoding.UTF8.GetBytes(Snapshot())).ConfigureAwait(false);
                        break;
                    default:
                        await Write(stream, 404, "text/plain", "Nothing here."u8.ToArray()).ConfigureAwait(false);
                        break;
                }
            }
            catch (Exception exception) when (exception is IOException or SocketException or ObjectDisposedException)
            {
            }
        }
    }

    /// What the phone draws: the numbers, not the logs behind them.
    private string Snapshot()
    {
        var now = DateTimeOffset.Now;
        var summary = new UsageSummary(store.Snapshot, now);
        var working = watcher.IsClaudeWorking(TimeSpan.FromSeconds(45));
        var turn = watcher.LastFinishedTurn;
        // Claude has stopped and the turn is fresh, so it is your move.
        var asking = !working && turn is not null && (now - turn.Date).TotalMinutes < 10;
        var seconds = store.Snapshot?.Session?.ResetsAt is { } reset && reset > now
            ? (int)(reset - now).TotalSeconds
            : 0;

        var payload = new Dictionary<string, object?>
        {
            ["plan"] = summary.PlanName,
            ["title"] = summary.Primary.Title,
            ["value"] = summary.Primary.Value,
            ["fraction"] = Math.Round(Math.Clamp(summary.Primary.Fraction, 0, 1), 4),
            ["severity"] = summary.Primary.Severity.ToString().ToLowerInvariant(),
            ["detail"] = summary.Primary.Detail,
            ["note"] = summary.Note,
            ["mood"] = summary.Mood.ToString().ToLowerInvariant(),
            ["working"] = working,
            ["activity"] = (watcher.Latest?.Activity ?? Activity.PetActivity.Idle).ToString().ToLowerInvariant(),
            ["asking"] = asking,
            ["turnId"] = turn?.Date.ToUnixTimeSeconds(),
            ["turnText"] = turn is null ? null : Format.Finished(turn),
            ["resetSeconds"] = seconds,
            ["today"] = summary.Activity is null ? null : Format.Tokens(summary.Activity.TodayTokens),
            ["requests"] = summary.Activity?.TodayMessages ?? 0,
            ["second"] = summary.Secondary.Count > 0
                ? new Dictionary<string, object?>
                {
                    ["title"] = summary.Secondary[0].Title,
                    ["value"] = summary.Secondary[0].Value,
                    ["fraction"] = Math.Round(Math.Clamp(summary.Secondary[0].Fraction, 0, 1), 4),
                    ["severity"] = summary.Secondary[0].Severity.ToString().ToLowerInvariant(),
                }
                : null,
        };
        return JsonSerializer.Serialize(payload);
    }

    private static async Task<(string Method, string Path, string Query)?> ReadRequest(NetworkStream stream)
    {
        var buffer = new byte[2048];
        var read = await stream.ReadAsync(buffer).ConfigureAwait(false);
        if (read <= 0) return null;
        var text = Encoding.ASCII.GetString(buffer, 0, read);
        var end = text.IndexOf('\r');
        if (end < 0) end = text.IndexOf('\n');
        if (end < 0) return null;

        var parts = text[..end].Split(' ');
        if (parts.Length < 2) return null;
        var target = parts[1];
        var mark = target.IndexOf('?');
        var path = mark < 0 ? target : target[..mark];
        var query = mark < 0 ? "" : target[(mark + 1)..];
        return (parts[0], path, query);
    }

    private static async Task Write(NetworkStream stream, int status, string type, byte[] body)
    {
        var reason = status switch
        {
            200 => "OK",
            401 => "Unauthorized",
            404 => "Not Found",
            405 => "Method Not Allowed",
            _ => "OK",
        };
        var head = $"HTTP/1.1 {status} {reason}\r\n"
                   + $"Content-Type: {type}\r\n"
                   + $"Content-Length: {body.Length}\r\n"
                   + "Cache-Control: no-store\r\n"
                   + "Connection: close\r\n\r\n";
        await stream.WriteAsync(Encoding.ASCII.GetBytes(head)).ConfigureAwait(false);
        await stream.WriteAsync(body).ConfigureAwait(false);
        await stream.FlushAsync().ConfigureAwait(false);
    }

    private static bool Matches(string query, string key)
    {
        foreach (var pair in query.Split('&'))
        {
            var mark = pair.IndexOf('=');
            if (mark < 0) continue;
            if (pair[..mark] != "k") continue;
            var given = Uri.UnescapeDataString(pair[(mark + 1)..]);
            return CryptographicOperations.FixedTimeEquals(
                Encoding.UTF8.GetBytes(given),
                Encoding.UTF8.GetBytes(key));
        }
        return false;
    }

    /// Only phones on the same home network are answered.
    private static bool IsHomeNetwork(IPAddress address)
    {
        if (IPAddress.IsLoopback(address)) return true;
        if (address.IsIPv4MappedToIPv6) address = address.MapToIPv4();
        if (address.AddressFamily == AddressFamily.InterNetworkV6)
        {
            return address.IsIPv6LinkLocal || address.IsIPv6SiteLocal;
        }
        var bytes = address.GetAddressBytes();
        return bytes[0] switch
        {
            10 => true,
            127 => true,
            169 => bytes[1] == 254,
            172 => bytes[1] >= 16 && bytes[1] <= 31,
            192 => bytes[1] == 168,
            _ => false,
        };
    }

    private static string? LocalAddress()
    {
        try
        {
            using var probe = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
            probe.Connect("8.8.8.8", 65530);
            return (probe.LocalEndPoint as IPEndPoint)?.Address.ToString();
        }
        catch (SocketException)
        {
            return null;
        }
    }

    /// The key lives in the settings file and can be changed by deleting it there.
    private static string Key()
    {
        var settings = Settings.Current;
        if (!string.IsNullOrEmpty(settings.MiniDisplayKey)) return settings.MiniDisplayKey;
        var fresh = Convert.ToHexString(RandomNumberGenerator.GetBytes(8)).ToLowerInvariant();
        settings.MiniDisplayKey = fresh;
        settings.Save();
        return fresh;
    }

    public void Dispose()
    {
        Settings.Changed -= Follow;
        lock (gate)
        {
            Close();
        }
    }
}
