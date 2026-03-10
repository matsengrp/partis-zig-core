/// ham/bcrham.zig — Zig port of ham/src/bcrham.cc
///
/// bcrham entry point: wires together Args, Track, GermLines, HMMHolder,
/// Sequences, DPHandler, and Glomerator.  The C++ `main()` is replaced here
/// by `run()`, which is called from cabi.zig's bcrham_run / bcrham_forward /
/// bcrham_viterbi stubs once they are implemented.
///
/// C++ source: packages/ham/src/bcrham.cc
/// C++ author: psathyrella/ham

const std = @import("std");
const Args = @import("args.zig").Args;
const Track = @import("track.zig").Track;
const Sequence = @import("sequences.zig").Sequence;
const bcr = @import("bcr_utils/root.zig");
const GermLines = bcr.GermLines;
const HMMHolder = bcr.HMMHolder;
const KSet = bcr.KSet;
const KBounds = bcr.KBounds;
const DPHandler = @import("dp_handler.zig").DPHandler;
const glomerator_mod = @import("glomerator/root.zig");
const Glomerator = glomerator_mod.Glomerator;
const bcr_utils = @import("bcr_utils/root.zig");

// ─── helpers ─────────────────────────────────────────────────────────────────

/// Build the flat list-of-lists of Sequence from parsed Args.
/// Corresponds to C++ `GetSeqs(args, trk)`.
pub fn getSeqs(
    allocator: std.mem.Allocator,
    args: *const Args,
    trk: *const Track,
) !std.ArrayListUnmanaged(std.ArrayListUnmanaged(Sequence)) {
    var all_seqs: std.ArrayListUnmanaged(std.ArrayListUnmanaged(Sequence)) = .{};
    errdefer {
        for (all_seqs.items) |*sv| {
            for (sv.items) |*sq| sq.deinit(allocator);
            sv.deinit(allocator);
        }
        all_seqs.deinit(allocator);
    }
    for (args.queries.items) |*qrow| {
        var seqs: std.ArrayListUnmanaged(Sequence) = .{};
        errdefer {
            for (seqs.items) |*sq| sq.deinit(allocator);
            seqs.deinit(allocator);
        }
        const n = qrow.names.items.len;
        for (0..n) |iseq| {
            const sq = try Sequence.initFromString(
                allocator,
                trk,
                qrow.names.items[iseq],
                qrow.seqs.items[iseq],
            );
            try seqs.append(allocator, sq);
        }
        try all_seqs.append(allocator, seqs);
    }
    return all_seqs;
}

// ─── run_algorithm ────────────────────────────────────────────────────────────

/// Run the Forward or Viterbi algorithm for each query and stream output.
/// Corresponds to C++ `run_algorithm(hmms, gl, qry_seq_list, args)`.
pub fn runAlgorithm(
    allocator: std.mem.Allocator,
    hmms: *HMMHolder,
    gl: *GermLines,
    qry_seq_list: *std.ArrayListUnmanaged(std.ArrayListUnmanaged(Sequence)),
    args: *Args,
    writer: anytype,
) !void {
    const bcr_text = @import("bcr_utils/utils.zig");
    try bcr_text.streamHeader(writer, args.algorithm);

    var n_vtb: i32 = 0;
    var n_fwd: i32 = 0;

    for (qry_seq_list.items, 0..) |*qseqs, iqry| {
        const qrow = &args.queries.items[iqry];
        const kmin = KSet{ .v = @intCast(qrow.k_v_min), .d = @intCast(qrow.k_d_min) };
        const kmax = KSet{ .v = @intCast(qrow.k_v_max), .d = @intCast(qrow.k_d_max) };
        const kbounds = KBounds.initFromSets(kmin, kmax);

        // Build only_genes slice ([]const []const u8) from qrow.only_genes
        const only_genes = try allocator.alloc([]const u8, qrow.only_genes.items.len);
        defer allocator.free(only_genes);
        for (qrow.only_genes.items, only_genes) |g, *out| out.* = g;

        var dph = try DPHandler.init(allocator, args.algorithm, args, gl, hmms);
        defer dph.deinit();

        var result = try dph.run(qseqs.items, kbounds, only_genes, @floatCast(qrow.mut_freq));
        defer result.deinit(allocator);

        if (result.no_path) {
            try bcr_text.streamErrorput(writer, args.algorithm, qseqs.items, "no_path");
        } else if (std.mem.eql(u8, args.algorithm, "viterbi")) {
            try bcr_text.streamViterbiOutput(writer, result.bestEvent(), qseqs.items, "");
        } else if (std.mem.eql(u8, args.algorithm, "forward")) {
            try bcr_text.streamForwardOutput(writer, qseqs.items, result.totalScore(), "");
        } else {
            return error.UnknownAlgorithm;
        }

        if (std.mem.eql(u8, args.algorithm, "viterbi"))
            n_vtb += 1
        else if (std.mem.eql(u8, args.algorithm, "forward"))
            n_fwd += 1;
    }
    std.debug.print("        calcd:   vtb {d:<4}  fwd {d:<4}\n", .{ n_vtb, n_fwd });
}

// ─── top-level run ────────────────────────────────────────────────────────────

/// Top-level bcrham run.  Corresponds to C++ `main()`.
/// `argv` is a slice of null-terminated argument strings (excluding argv[0]).
pub fn run(allocator: std.mem.Allocator, argv: []const [*:0]const u8) !void {
    const start = std.time.milliTimestamp();

    // Parse args from argv
    var args = try Args.initFromArgv(allocator, argv);
    defer args.deinit(allocator);

    // Build track
    const characters = [_][]const u8{ "A", "C", "G", "T" };
    var track = try Track.init(allocator, "NUKES");
    defer track.deinit(allocator);
    for (characters) |c| {
        try track.addAlphabet(allocator, c);
    }
    try track.setAmbiguousChar(allocator, args.ambig_base);

    // Load germlines and HMMs
    var gl = try GermLines.init(allocator, args.datadir, args.locus);
    defer gl.deinit(allocator);

    var hmms = try HMMHolder.init(allocator, args.hmmdir, &gl, &track);
    defer hmms.deinit(allocator);

    // Build query sequences
    var qry_seq_list = try getSeqs(allocator, &args, &track);
    defer {
        for (qry_seq_list.items) |*sv| {
            for (sv.items) |*sq| sq.deinit(allocator);
            sv.deinit(allocator);
        }
        qry_seq_list.deinit(allocator);
    }

    // Open outfile
    const outfile = try std.fs.createFileAbsolute(args.outfile, .{});
    defer outfile.close();
    var bw = std.io.bufferedWriter(outfile.writer());

    if (args.cache_naive_seqs) {
        var glom = try Glomerator.init(allocator, &hmms, &gl, &qry_seq_list, &args, &track);
        defer glom.deinit();
        try glom.cacheNaiveSeqs();
    } else if (args.partition) {
        var glom = try Glomerator.init(allocator, &hmms, &gl, &qry_seq_list, &args, &track);
        defer glom.deinit();
        try glom.cluster();
    } else {
        try runAlgorithm(allocator, &hmms, &gl, &qry_seq_list, &args, bw.writer());
    }

    try bw.flush();

    const elapsed_s = @as(f64, @floatFromInt(std.time.milliTimestamp() - start)) / 1000.0;
    std.debug.print("        time: bcrham {d:.1}\n", .{elapsed_s});
}
