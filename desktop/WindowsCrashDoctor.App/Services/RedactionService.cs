using System.Text.RegularExpressions;

namespace WindowsCrashDoctor.Services;

public sealed record SensitiveMatch(string PatternType, int LineNumber);
public sealed record RedactionResult(string Text, IReadOnlyList<SensitiveMatch> Matches)
{
    public int Count => Matches.Count;
}

public sealed class RedactionService
{
    private sealed record Rule(string Name, Regex Pattern, string Replacement);

    private static readonly IReadOnlyList<Rule> Rules = new List<Rule>
    {
        new("bitlocker-recovery-password", new Regex(@"(?<!\d)(?:\d{6}-){7}\d{6}(?!\d)", RegexOptions.Compiled), "[REDACTED_BITLOCKER_RECOVERY_PASSWORD]"),
        new("openai-api-key", new Regex(@"\bsk-(?:proj-)?[A-Za-z0-9_-]{20,}\b", RegexOptions.Compiled), "[REDACTED_API_KEY]"),
        new("anthropic-api-key", new Regex(@"\bsk-ant-[A-Za-z0-9_-]{20,}\b", RegexOptions.Compiled), "[REDACTED_API_KEY]"),
        new("github-token", new Regex(@"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b", RegexOptions.Compiled | RegexOptions.IgnoreCase), "[REDACTED_TOKEN]"),
        new("aws-access-key-id", new Regex(@"\b(?:AKIA|ASIA|AIDA|AROA|AIPA|ANPA|ANVA)[A-Z0-9]{16}\b", RegexOptions.Compiled), "[REDACTED_AWS_ACCESS_KEY_ID]"),
        new("jwt", new Regex(@"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b", RegexOptions.Compiled), "[REDACTED_JWT]"),
        new("bearer-token", new Regex(@"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{12,}", RegexOptions.Compiled), "Bearer [REDACTED_TOKEN]"),
        new("credential-field", new Regex(@"(?im)(\b(?:password|passwd|pwd|api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|secret)\b\s*[:=]\s*)(?!\[REDACTED_)([^\s,;]+)", RegexOptions.Compiled), "$1[REDACTED_SECRET]"),
        new("email-address", new Regex(@"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", RegexOptions.Compiled | RegexOptions.IgnoreCase), "[REDACTED_EMAIL]"),
        new("windows-user-path", new Regex(@"(?i)C:\\Users\\[^\\\s]+", RegexOptions.Compiled), @"C:\Users\[REDACTED_USER]"),
        new("mac-address", new Regex(@"(?i)\b(?:[0-9A-F]{2}[:-]){5}[0-9A-F]{2}\b", RegexOptions.Compiled), "[REDACTED_MAC]")
    };

    private static readonly Regex PrivateKeyMarker = new(
        @"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);

    public RedactionResult Redact(string input)
    {
        if (string.IsNullOrEmpty(input)) return new RedactionResult(input, Array.Empty<SensitiveMatch>());
        var matches = Scan(input).ToList();
        var output = input;
        foreach (var rule in Rules) output = rule.Pattern.Replace(output, rule.Replacement);
        return new RedactionResult(output, matches);
    }

    public IReadOnlyList<SensitiveMatch> Scan(string input)
    {
        if (string.IsNullOrEmpty(input)) return Array.Empty<SensitiveMatch>();
        var matches = new List<SensitiveMatch>();
        foreach (var rule in Rules)
            foreach (Match match in rule.Pattern.Matches(input))
                matches.Add(new SensitiveMatch(rule.Name, GetLineNumber(input, match.Index)));
        foreach (Match match in PrivateKeyMarker.Matches(input))
            matches.Add(new SensitiveMatch("private-key-material", GetLineNumber(input, match.Index)));
        return matches.OrderBy(x => x.LineNumber).ThenBy(x => x.PatternType, StringComparer.Ordinal).ToList();
    }

    public bool ContainsPrivateKeyMaterial(string input) => !string.IsNullOrEmpty(input) && PrivateKeyMarker.IsMatch(input);

    public string RedactForLog(string input)
    {
        var text = Redact(input).Text.Replace('\r', ' ').Replace('\n', ' ').Trim();
        return text.Length <= 1000 ? text : text[..1000] + "…";
    }

    private static int GetLineNumber(string text, int index)
    {
        var line = 1;
        for (var i = 0; i < index && i < text.Length; i++) if (text[i] == '\n') line++;
        return line;
    }
}
