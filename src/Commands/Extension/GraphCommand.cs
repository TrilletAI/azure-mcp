// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

using System.Runtime.InteropServices;
using AzureMcp.Models.Option;
using AzureMcp.Options.Extension;
using AzureMcp.Services.Azure;
using AzureMcp.Services.Interfaces;
using Microsoft.Extensions.Logging;

namespace AzureMcp.Commands.Extension;

public sealed class GraphCommand(ILogger<GraphCommand> logger, int processTimeoutSeconds = 300) : GlobalCommand<GraphOptions>()
{
    private const string _commandTitle = "Microsoft Graph CLI Command";
    private readonly ILogger<GraphCommand> _logger = logger;
    private readonly int _processTimeoutSeconds = processTimeoutSeconds;
    private readonly Option<string> _commandOption = OptionDefinitions.Extension.Graph.Command;
    private static string? _cachedMgcPath;
    private volatile bool _isAuthenticated = false;
    private static readonly SemaphoreSlim _authSemaphore = new(1, 1);

    private static readonly string[] MgcPaths =
    [
        // Windows
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".local", "bin"),
        // Linux and MacOS
        Path.Combine("usr", "local", "bin"),
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".local", "bin"),
    ];

    public override string Name => "graph";

    public override string Description =>
        """
        Runs Microsoft Graph CLI (mgc) commands.
        This tool can be used to manage Microsoft Graph resources, like users, groups, etc.

        If unsure about available commands or their parameters, run mgc --help or mgc <group> --help in the command to discover them.
        """;

    public override string Title => _commandTitle;

    protected override void RegisterOptions(Command command)
    {
        base.RegisterOptions(command);
        command.AddOption(_commandOption);
    }

    protected override GraphOptions BindOptions(ParseResult parseResult)
    {
        var options = base.BindOptions(parseResult);
        options.Command = parseResult.GetValueForOption(_commandOption);

        return options;
    }

    private async Task<bool> AuthenticateWithAzureCredentialsAsync(IExternalProcessService processService, ILogger logger)
    {
        if (_isAuthenticated)
        {
            return true;
        }

        await _authSemaphore.WaitAsync();
        try
        {
            // Double-check after acquiring the lock
            if (_isAuthenticated)
            {
                return true;
            }

            // The mgc CLI will automatically use the AZURE_* environment variables 
            // when --strategy Environment is used. These variables are set in the 
            // deployment environment (e.g., App Service Configuration).
            var clientId = Environment.GetEnvironmentVariable("AZURE_CLIENT_ID");
            if (string.IsNullOrEmpty(clientId))
            {
                logger.LogInformation("AZURE_CLIENT_ID environment variable not set. Skipping service principal login for mgc.");
                return false;
            }

            var mgcPath = FindMgcPath() ?? throw new FileNotFoundException("Microsoft Graph CLI executable not found.");

            var loginCommand = "login --strategy Environment";
            var result = await processService.ExecuteAsync(mgcPath, loginCommand, 60);

            if (result.ExitCode != 0)
            {
                logger.LogError("Failed to authenticate with Microsoft Graph CLI using service principal. Exit Code: {ExitCode}, Error: {Error}", result.ExitCode, result.Error);
                return false;
            }

            _isAuthenticated = true;
            logger.LogInformation("Successfully authenticated with Microsoft Graph CLI using service principal.");
            return true;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Exception during service principal authentication for MGC.");
            return false;
        }
        finally
        {
            _authSemaphore.Release();
        }
    }

    [McpServerTool(Destructive = false, ReadOnly = true, Title = _commandTitle)]
    public override async Task<CommandResponse> ExecuteAsync(CommandContext context, ParseResult parseResult)
    {
        var options = BindOptions(parseResult);

        try
        {
            if (!Validate(parseResult.CommandResult, context.Response).IsValid)
            {
                return context.Response;
            }
            
            ArgumentNullException.ThrowIfNull(options.Command);

            var command = options.Command;

            var processService = context.GetService<IExternalProcessService>();

            await AuthenticateWithAzureCredentialsAsync(processService, _logger);

            var mgcPath = FindMgcPath() ?? throw new FileNotFoundException("Microsoft Graph CLI executable not found in PATH or common installation locations. Please ensure Microsoft Graph CLI is installed.");
            var result = await processService.ExecuteAsync(mgcPath, command, _processTimeoutSeconds);

            if (string.IsNullOrWhiteSpace(result.Error) && result.ExitCode == 0)
            {
                return HandleSuccess(result, command, context.Response);
            }
            else
            {
                return HandleError(result, context.Response);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "An exception occurred executing command. Command: {Command}.", options.Command);
            HandleException(context.Response, ex);
        }

        return context.Response;
    }

    private static string? FindMgcPath()
    {
        // Return cached path if available and still exists
        if (!string.IsNullOrEmpty(_cachedMgcPath) && File.Exists(_cachedMgcPath))
        {
            return _cachedMgcPath;
        }

        var isWindows = RuntimeInformation.IsOSPlatform(OSPlatform.Windows);

        // Add PATH environment directories followed by the common installation locations
        // This will capture any custom MGC installations as well as standard installations.
        var searchPaths = new List<string>();
        if (Environment.GetEnvironmentVariable("PATH")?.Split(Path.PathSeparator) is { } pathDirs)
        {
            searchPaths.AddRange(pathDirs);
        }

        searchPaths.AddRange(MgcPaths);

        foreach (var dir in searchPaths.Where(d => !string.IsNullOrEmpty(d)))
        {
            if (isWindows)
            {
                var cmdPath = Path.Combine(dir, "mgc.exe");
                if (File.Exists(cmdPath))
                {
                    _cachedMgcPath = cmdPath;
                    return cmdPath;
                }
            }
            else
            {
                var fullPath = Path.Combine(dir, "mgc");
                if (File.Exists(fullPath))
                {
                    _cachedMgcPath = fullPath;
                    return fullPath;
                }
            }
        }

        return null;
    }

    private static CommandResponse HandleSuccess(ProcessResult result, string command, CommandResponse response)
    {
        var contentResults = new List<string>();
        if (!string.IsNullOrWhiteSpace(result.Output))
        {
            contentResults.Add(result.Output);
        }
        
        response.Results = ResponseResult.Create(contentResults, JsonSourceGenerationContext.Default.ListString);

        return response;
    }

    private static CommandResponse HandleError(ProcessResult result, CommandResponse response)
    {
        response.Status = 500;
        response.Message = result.Error;

        var contentResults = new List<string>
            {
                result.Output
            };
            
        response.Results = ResponseResult.Create(contentResults, JsonSourceGenerationContext.Default.ListString);

        return response;
    }
} 