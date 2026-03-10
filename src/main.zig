/// main.zig — partis-zig-core executable entry point.
///
/// Accepts the same CLI arguments as bcrham so the equivalence harness can
/// compare checkpoint streams side-by-side.
///
/// Required arguments (matching bcrham):
///   --hmmdir   <dir>   directory containing per-gene HMM YAML files
///   --datadir  <dir>   directory containing germline FASTA files
///   --infile   <file>  whitespace-separated query CSV (names/seqs/only_genes/…)
///   --outfile  <file>  output CSV path
///   --algorithm        viterbi|forward
///   --locus            igh|igk|igl|tra|trb|trg|trd
///
/// As components are ported, their logic replaces the @panic stubs below.
/// Checkpoint JSON is emitted to stderr, matching the C++ instrumentation.
///
/// Checkpoint sequence replicates bcrham's Args constructor + GermLines constructor:
///   1. SplitString × N_str_list_cols per data row (names, seqs, only_genes)
///   2. SplitString × (1 + N_data_rows) for extras.csv (header + each data row)
///   3. ClearWhitespace on each sequence string (strips '\n' as C++ Sequence does)

const std = @import("std");
const ham_text = @import("ham/text.zig");

const ParsedArgs = struct {
    hmmdir: []u8,
    datadir: []u8,
    infile: []u8,
    outfile: []u8,
    algorithm: []u8,
    locus: []u8,
};

fn parseArgs(allocator: std.mem.Allocator) !ParsedArgs {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var hmmdir: ?[]u8 = null;
    var datadir: ?[]u8 = null;
    var infile: ?[]u8 = null;
    var outfile: ?[]u8 = null;
    var algorithm: ?[]u8 = null;
    var locus: ?[]u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--hmmdir") and i + 1 < args.len) {
            i += 1;
            hmmdir = try allocator.dupe(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "--datadir") and i + 1 < args.len) {
            i += 1;
            datadir = try allocator.dupe(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "--infile") and i + 1 < args.len) {
            i += 1;
            infile = try allocator.dupe(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "--outfile") and i + 1 < args.len) {
            i += 1;
            outfile = try allocator.dupe(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "--algorithm") and i + 1 < args.len) {
            i += 1;
            algorithm = try allocator.dupe(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "--locus") and i + 1 < args.len) {
            i += 1;
            locus = try allocator.dupe(u8, args[i]);
        }
        // Ignore unknown flags for forward-compatibility (bcrham has many optional flags)
    }

    return ParsedArgs{
        .hmmdir = hmmdir orelse return error.MissingArgHmmdir,
        .datadir = datadir orelse return error.MissingArgDatadir,
        .infile = infile orelse return error.MissingArgInfile,
        .outfile = outfile orelse return error.MissingArgOutfile,
        .algorithm = algorithm orelse return error.MissingArgAlgorithm,
        .locus = locus orelse return error.MissingArgLocus,
    };
}

/// Represents one row of the bcrham whitespace-separated infile.
/// Column order: names k_v_min k_v_max k_d_min k_d_max mut_freq cdr3_length only_genes seqs
const QueryRow = struct {
    names: []u8,      // colon-separated, owned
    k_v_min: i32,
    k_v_max: i32,
    k_d_min: i32,
    k_d_max: i32,
    mut_freq: f64,
    cdr3_length: i32,
    only_genes: []u8, // colon-separated, owned
    seqs: []u8,       // colon-separated, owned
};

/// Header types matching bcrham's Args constructor.
/// str_list_headers: split by ":" via SplitString
/// int_headers:      parsed directly via ss >> int (no Intify/SplitString)
/// float_headers:    parsed directly via ss >> float (no Floatify/SplitString)
const STR_LIST_HEADERS = [_][]const u8{ "names", "seqs", "only_genes" };
const INT_HEADERS = [_][]const u8{ "k_v_min", "k_v_max", "k_d_min", "k_d_max", "cdr3_length" };
const FLOAT_HEADERS = [_][]const u8{"mut_freq"};

fn isStrListHeader(name: []const u8) bool {
    for (STR_LIST_HEADERS) |h| if (std.mem.eql(u8, h, name)) return true;
    return false;
}

fn isIntHeader(name: []const u8) bool {
    for (INT_HEADERS) |h| if (std.mem.eql(u8, h, name)) return true;
    return false;
}

fn isFloatHeader(name: []const u8) bool {
    for (FLOAT_HEADERS) |h| if (std.mem.eql(u8, h, name)) return true;
    return false;
}

/// Read and parse the bcrham infile, replicating bcrham's Args constructor
/// checkpoint sequence exactly.
///
/// For str_list columns (names, seqs, only_genes): calls SplitString(col, ":")
/// For int columns (k_v_min etc.): parses directly, no SplitString/Intify
/// For float columns (mut_freq): parses directly, no SplitString/Floatify
fn readInfile(allocator: std.mem.Allocator, path: []const u8) !std.ArrayList(QueryRow) {
    const data = try std.fs.cwd().readFileAlloc(allocator, path, 64 * 1024 * 1024);
    defer allocator.free(data);

    var rows: std.ArrayList(QueryRow) = .empty;
    var lines = std.mem.splitScalar(u8, data, '\n');
    var header_parsed = false;
    var col_names: std.ArrayList([]u8) = .empty;
    defer {
        for (col_names.items) |c| allocator.free(c);
        col_names.deinit(allocator);
    }

    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \r\t");
        if (line.len == 0) continue;

        if (!header_parsed) {
            header_parsed = true;
            // Parse header using whitespace tokenization (no checkpoint emitted — C++ uses
            // stringstream >> which also does not call any ham::Text function).
            var it = std.mem.tokenizeAny(u8, line, " \t");
            while (it.next()) |tok| {
                if (tok.len > 0)
                    try col_names.append(allocator, try allocator.dupe(u8, tok));
            }
            continue;
        }

        // Skip very short lines (C++ uses line.size() < 10)
        if (line.len < 10) continue;

        // Tokenize data row by whitespace
        var field_parts: std.ArrayList([]const u8) = .empty;
        defer field_parts.deinit(allocator);
        var fit = std.mem.tokenizeAny(u8, line, " \t");
        while (fit.next()) |tok| {
            try field_parts.append(allocator, tok);
        }
        if (field_parts.items.len == 0) continue;
        if (field_parts.items.len != col_names.items.len) {
            std.debug.print("WARNING: infile row has {d} fields, expected {d}; skipping\n",
                .{ field_parts.items.len, col_names.items.len });
            continue;
        }

        // Build a column-name → raw-field-value map
        var row_map = std.StringHashMap([]const u8).init(allocator);
        defer row_map.deinit();
        for (col_names.items, field_parts.items) |col, val| {
            try row_map.put(col, val);
        }

        // Iterate columns in order (matching C++ `for(auto &head : headers)`)
        // For str_list columns, call SplitString (emits checkpoint) then free parts.
        // For int/float columns, parse directly — no ham::Text call.
        var names_raw: []const u8 = "";
        var seqs_raw: []const u8 = "";
        var only_genes_raw: []const u8 = "";
        var k_v_min: i32 = 0;
        var k_v_max: i32 = 0;
        var k_d_min: i32 = 0;
        var k_d_max: i32 = 0;
        var cdr3_length: i32 = 0;
        var mut_freq: f64 = 0.0;
        var ok = true;

        for (col_names.items) |col| {
            const val = row_map.get(col) orelse {
                ok = false;
                break;
            };
            if (isStrListHeader(col)) {
                // C++ calls SplitString(tmpstr, ":") then stores the result
                var parts = try ham_text.split_string(allocator, val, ":");
                defer {
                    for (parts.items) |p| allocator.free(p);
                    parts.deinit(allocator);
                }
                // Store the raw colon-separated string for later use
                if (std.mem.eql(u8, col, "names")) names_raw = val;
                if (std.mem.eql(u8, col, "seqs")) seqs_raw = val;
                if (std.mem.eql(u8, col, "only_genes")) only_genes_raw = val;
            } else if (isIntHeader(col)) {
                const v = std.fmt.parseInt(i32, val, 10) catch { ok = false; break; };
                if (std.mem.eql(u8, col, "k_v_min")) k_v_min = v;
                if (std.mem.eql(u8, col, "k_v_max")) k_v_max = v;
                if (std.mem.eql(u8, col, "k_d_min")) k_d_min = v;
                if (std.mem.eql(u8, col, "k_d_max")) k_d_max = v;
                if (std.mem.eql(u8, col, "cdr3_length")) cdr3_length = v;
            } else if (isFloatHeader(col)) {
                const v = std.fmt.parseFloat(f64, val) catch { ok = false; break; };
                if (std.mem.eql(u8, col, "mut_freq")) mut_freq = v;
            }
        }
        if (!ok) continue;
        if (names_raw.len == 0 or seqs_raw.len == 0) continue;

        try rows.append(allocator, QueryRow{
            .names = try allocator.dupe(u8, names_raw),
            .k_v_min = k_v_min,
            .k_v_max = k_v_max,
            .k_d_min = k_d_min,
            .k_d_max = k_d_max,
            .mut_freq = mut_freq,
            .cdr3_length = cdr3_length,
            .only_genes = try allocator.dupe(u8, only_genes_raw),
            .seqs = try allocator.dupe(u8, seqs_raw),
        });
    }
    return rows;
}

/// Read extras.csv from germline dir, replicating bcrham's GermLines constructor
/// checkpoint sequence:
///   SplitString(header_line, ",") — 1 checkpoint
///   SplitString(data_line, ",")   — 1 checkpoint per data row
fn readExtras(allocator: std.mem.Allocator, datadir: []const u8, locus: []const u8) !void {
    var path_buf: [4096]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/{s}/extras.csv", .{ datadir, locus });

    const data = std.fs.cwd().readFileAlloc(allocator, path, 4 * 1024 * 1024) catch |err| {
        std.debug.print("WARNING: could not read extras.csv at {s}: {}\n", .{ path, err });
        return;
    };
    defer allocator.free(data);

    var lines = std.mem.splitScalar(u8, data, '\n');
    var first = true;
    while (lines.next()) |raw_line| {
        // C++ strips \r: line.erase(remove(..., '\r'), ...)
        const line = std.mem.trim(u8, raw_line, "\r");
        if (line.len == 0) continue;
        // Call SplitString(line, ",") — emits checkpoint
        var parts = try ham_text.split_string(allocator, line, ",");
        defer {
            for (parts.items) |p| allocator.free(p);
            parts.deinit(allocator);
        }
        if (first) {
            // Validate header (gene, cyst_position, tryp_position, phen_position, ...)
            first = false;
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const parsed = parseArgs(allocator) catch |err| {
        std.debug.print("ERROR: missing required argument: {}\n", .{err});
        std.debug.print("usage: partis-zig-core --hmmdir <dir> --datadir <dir> --infile <file> --outfile <file> --algorithm <viterbi|forward> --locus <locus>\n", .{});
        std.process.exit(1);
    };
    defer {
        allocator.free(parsed.hmmdir);
        allocator.free(parsed.datadir);
        allocator.free(parsed.infile);
        allocator.free(parsed.outfile);
        allocator.free(parsed.algorithm);
        allocator.free(parsed.locus);
    }

    // 1. Read infile — calls SplitString for str_list columns (names, seqs, only_genes)
    var rows = try readInfile(allocator, parsed.infile);
    defer {
        for (rows.items) |row| {
            allocator.free(row.names);
            allocator.free(row.only_genes);
            allocator.free(row.seqs);
        }
        rows.deinit(allocator);
    }

    // 2. Read extras.csv from datadir/<locus>/ — calls SplitString per line (header + data)
    try readExtras(allocator, parsed.datadir, parsed.locus);

    // 3. For each sequence, call ClearWhitespace('\n', seq) — as Sequence constructor does.
    // The seqs were already split by SplitString in readInfile; iterate those stored parts
    // without a second SplitString call.
    for (rows.items) |row| {
        // row.seq_parts are the individual sequences (from the SplitString in readInfile).
        // We iterate them directly and call ClearWhitespace on each.
        var it = std.mem.splitScalar(u8, row.seqs, ':');
        while (it.next()) |seq_str| {
            var seq_buf: std.ArrayList(u8) = .empty;
            defer seq_buf.deinit(allocator);
            try seq_buf.appendSlice(allocator, seq_str);
            ham_text.clear_whitespace(allocator, "\n", &seq_buf);
        }
    }

    // 4. Write outfile header (stub — real output will come from ported components)
    const outfile = try std.fs.cwd().createFile(parsed.outfile, .{});
    defer outfile.close();
    if (std.mem.eql(u8, parsed.algorithm, "forward")) {
        try outfile.writeAll("unique_ids logprob\n");
    } else {
        try outfile.writeAll("unique_ids v_gene d_gene j_gene\n");
    }

    // 5. Emit stub output rows
    var line_buf: [4096]u8 = undefined;
    for (rows.items) |row| {
        if (std.mem.eql(u8, parsed.algorithm, "forward")) {
            const line = try std.fmt.bufPrint(&line_buf, "{s} not_yet_implemented\n", .{row.names});
            try outfile.writeAll(line);
        } else {
            const line = try std.fmt.bufPrint(&line_buf, "{s} not_yet_implemented not_yet_implemented not_yet_implemented\n", .{row.names});
            try outfile.writeAll(line);
        }
    }

    const n_fwd = if (std.mem.eql(u8, parsed.algorithm, "forward")) rows.items.len else 0;
    const n_vtb = if (std.mem.eql(u8, parsed.algorithm, "viterbi")) rows.items.len else 0;
    std.debug.print("        calcd:   vtb {d}     fwd {d}\n", .{ n_vtb, n_fwd });
    std.debug.print("        time: partis-zig-core 0.0\n", .{});
}
