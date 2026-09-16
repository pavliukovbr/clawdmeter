using System.IO;
using System.Text.Json;

namespace Clawdmeter;

public enum KeepAwakeMode { Off, WhileClaudeWorks, Always }

/// Everything the user can switch on or off, kept in a small file next to the snapshot.
public sealed class Settings
{
    private static readonly object Lock = new();
    private static Settings? current;

    public static string Folder => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "Clawdmeter");

    private static string FilePath => Path.Combine(Folder, "settings.json");

    public static Settings Current
    {
        get
        {
            lock (Lock)
            {
                return current ??= Load();
            }
        }
    }

    /// Raised on the thread that saved, so listeners hop to the UI thread themselves.
    public static event Action? Changed;

    public bool PetWalksAround { get; set; } = true;
    public bool ShowPanel { get; set; } = true;
    public bool PanelAlwaysOnTop { get; set; } = true;
    public bool NotifyWhenClaudeFinishes { get; set; } = true;
    public KeepAwakeMode KeepAwake { get; set; } = KeepAwakeMode.Off;
    public bool KeepDisplayOn { get; set; }
    public bool RunAtStartup { get; set; }
    public bool UpdateAutomatically { get; set; } = true;
    /// Serves a small usage page on the home network for an old phone to keep open.
    public bool MiniDisplay { get; set; }
    public string MiniDisplayKey { get; set; } = "";
    public double? PanelLeft { get; set; }
    public double? PanelTop { get; set; }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Folder);
            var json = JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(FilePath, json);
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
        Changed?.Invoke();
    }

    private static Settings Load()
    {
        try
        {
            if (File.Exists(FilePath))
            {
                var loaded = JsonSerializer.Deserialize<Settings>(File.ReadAllText(FilePath));
                if (loaded is not null) return loaded;
            }
        }
        catch (Exception exception) when (exception is IOException or JsonException or UnauthorizedAccessException)
        {
        }
        return new Settings();
    }
}
