// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

using AzureMcp.Options.Postgres;

namespace AzureMcp.Options.Extension;

public sealed class GraphOptions : GlobalOptions
{
    public string? Command { get; set; }
} 