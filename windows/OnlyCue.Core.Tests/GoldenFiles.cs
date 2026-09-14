using System.Text.Json;

namespace OnlyCue.Core.Tests;

/// <summary>
/// Shared locator/loader for the committed golden-vector contracts under
/// <c>golden/</c>. macOS is the source of truth for every one of them; this side
/// only ever reads.
/// </summary>
internal static class GoldenFiles
{
    /// <summary>The repo root, found by walking up from the test assembly until
    /// the xcodegen marker is visible — the same marker the Swift side uses in
    /// <c>OnlyCueTests/Support/RepoRootLocating.swift</c>. Keeps the verifier
    /// independent of where the build output lands (local <c>bin/</c> vs the CI
    /// runner's workspace).</summary>
    public static string RepoRoot { get; } = FindRepoRoot();

    public static T Load<T>(string relativePath)
    {
        var path = Path.Combine(RepoRoot, relativePath);
        var json = File.ReadAllText(path);
        return JsonSerializer.Deserialize<T>(json)
            ?? throw new InvalidDataException($"{path} did not deserialize to {typeof(T).Name}");
    }

    private static string FindRepoRoot()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null)
        {
            if (File.Exists(Path.Combine(dir.FullName, "project.yml")))
            {
                return dir.FullName;
            }

            dir = dir.Parent;
        }

        throw new FileNotFoundException(
            $"could not locate project.yml in any ancestor of {AppContext.BaseDirectory} — "
            + "the repo checkout looks incomplete");
    }
}
