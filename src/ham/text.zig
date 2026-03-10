/// ham/text.zig — Zig port of ham/src/text.cc
///
/// String utility functions used pervasively throughout ham.
/// All functions in namespace ham::Text.
///
/// C++ source: packages/ham/src/text.cc, packages/ham/include/text.h
/// C++ author: psathyrella/ham

const std = @import("std");

/// Removes all instances of characters in `chars` from `input` in place.
/// Corresponds to C++ `ham::ClearWhitespace(string white, string *input)`.
pub fn clear_whitespace(chars: []const u8, input: *std.ArrayList(u8)) void {
    var i: usize = 0;
    while (i < input.items.len) {
        if (std.mem.indexOfScalar(u8, chars, input.items[i]) != null) {
            _ = input.orderedRemove(i);
            // do not advance i — recheck same position
        } else {
            i += 1;
        }
    }
    std.debug.print("{{\"checkpoint\": \"ham.Text.ClearWhitespace.exit\", \"result\": \"{s}\"}}\n", .{input.items});
}

/// Splits `argstr` by whitespace (any run), returning a slice of owned slices.
/// Caller owns the returned ArrayList and its items.
/// Corresponds to C++ `ham::PythonSplit(string argstr)`.
pub fn python_split(allocator: std.mem.Allocator, argstr: []const u8) !std.ArrayList([]u8) {
    var tokens = std.ArrayList([]u8).init(allocator);
    var it = std.mem.tokenizeAny(u8, argstr, " \t\n\r");
    while (it.next()) |tok| {
        const owned = try allocator.dupe(u8, tok);
        try tokens.append(owned);
    }
    std.debug.print("{{\"checkpoint\": \"ham.Text.PythonSplit.exit\", \"n_tokens\": {}}}\n", .{tokens.items.len});
    return tokens;
}

/// Splits `argstr` by `delimiter`, returning owned slices.
/// Default delimiter in C++ is `":"`.
/// Corresponds to C++ `ham::SplitString(string argstr, string delimiter)`.
pub fn split_string(allocator: std.mem.Allocator, argstr: []const u8, delimiter: []const u8) !std.ArrayList([]u8) {
    var parts = std.ArrayList([]u8).init(allocator);
    var remaining = argstr;
    while (true) {
        if (std.mem.indexOf(u8, remaining, delimiter)) |pos| {
            const part = try allocator.dupe(u8, remaining[0..pos]);
            try parts.append(part);
            remaining = remaining[pos + delimiter.len ..];
        } else {
            // last (or only) segment
            const part = try allocator.dupe(u8, remaining);
            try parts.append(part);
            break;
        }
    }
    std.debug.print("{{\"checkpoint\": \"ham.Text.SplitString.exit\", \"n_parts\": {}}}\n", .{parts.items.len});
    return parts;
}

/// Returns true if `query` is found as a delimited token in `liststr`.
/// Default delimiter in C++ is `":"`.
/// Corresponds to C++ `ham::InString(string query, string liststr, string delimiter)`.
pub fn in_string(query: []const u8, liststr: []const u8, delimiter: []const u8) bool {
    var remaining = liststr;
    while (true) {
        if (std.mem.indexOf(u8, remaining, delimiter)) |pos| {
            if (std.mem.eql(u8, remaining[0..pos], query)) {
                std.debug.print("{{\"checkpoint\": \"ham.Text.InString.exit\", \"found\": true}}\n", .{});
                return true;
            }
            remaining = remaining[pos + delimiter.len ..];
        } else {
            if (std.mem.eql(u8, remaining, query)) {
                std.debug.print("{{\"checkpoint\": \"ham.Text.InString.exit\", \"found\": true}}\n", .{});
                return true;
            }
            break;
        }
    }
    std.debug.print("{{\"checkpoint\": \"ham.Text.InString.exit\", \"found\": false}}\n", .{});
    return false;
}

/// Joins a slice of strings with `delimiter` between each pair.
/// Returns owned string. Caller owns the result.
/// Corresponds to C++ `ham::JoinStrings(vector<string> &strlist, string delimiter)`.
pub fn join_strings(allocator: std.mem.Allocator, strlist: []const []const u8, delimiter: []const u8) ![]u8 {
    if (strlist.len == 0) {
        const result = try allocator.dupe(u8, "");
        std.debug.print("{{\"checkpoint\": \"ham.Text.JoinStrings.exit\", \"result\": \"\"}}\n", .{});
        return result;
    }
    var total_len: usize = 0;
    for (strlist, 0..) |s, i| {
        total_len += s.len;
        if (i + 1 < strlist.len) total_len += delimiter.len;
    }
    const buf = try allocator.alloc(u8, total_len);
    var pos: usize = 0;
    for (strlist, 0..) |s, i| {
        @memcpy(buf[pos .. pos + s.len], s);
        pos += s.len;
        if (i + 1 < strlist.len) {
            @memcpy(buf[pos .. pos + delimiter.len], delimiter);
            pos += delimiter.len;
        }
    }
    std.debug.print("{{\"checkpoint\": \"ham.Text.JoinStrings.exit\", \"result\": \"{s}\"}}\n", .{buf});
    return buf;
}

/// Converts a slice of strings to a slice of i32.
/// Corresponds to C++ `ham::Intify(vector<string> strlist)` (uses stoi → int).
pub fn intify(allocator: std.mem.Allocator, strlist: []const []const u8) ![]i32 {
    const result = try allocator.alloc(i32, strlist.len);
    for (strlist, 0..) |s, i| {
        result[i] = try std.fmt.parseInt(i32, s, 10);
    }
    std.debug.print("{{\"checkpoint\": \"ham.Text.Intify.exit\", \"n\": {}}}\n", .{result.len});
    return result;
}

/// Converts a slice of strings to a slice of f64.
/// C++ uses stof (f32 precision) but returns vector<double>; we parse as f32 then widen to f64 to match.
/// Corresponds to C++ `ham::Floatify(vector<string> strlist)`.
pub fn floatify(allocator: std.mem.Allocator, strlist: []const []const u8) ![]f64 {
    const result = try allocator.alloc(f64, strlist.len);
    for (strlist, 0..) |s, i| {
        // C++ uses stof (single-precision parse) — match that precision by parsing as f32 then widening
        const f32_val = try std.fmt.parseFloat(f32, s);
        result[i] = @as(f64, f32_val);
    }
    std.debug.print("{{\"checkpoint\": \"ham.Text.Floatify.exit\", \"n\": {}}}\n", .{result.len});
    return result;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

test "split_string default delimiter" {
    const allocator = std.testing.allocator;
    var parts = try split_string(allocator, "a:b:c", ":");
    defer {
        for (parts.items) |p| allocator.free(p);
        parts.deinit();
    }
    try std.testing.expectEqual(@as(usize, 3), parts.items.len);
    try std.testing.expectEqualStrings("a", parts.items[0]);
    try std.testing.expectEqualStrings("b", parts.items[1]);
    try std.testing.expectEqualStrings("c", parts.items[2]);
}

test "in_string found" {
    try std.testing.expect(in_string("b", "a:b:c", ":"));
}

test "in_string not found" {
    try std.testing.expect(!in_string("d", "a:b:c", ":"));
}

test "join_strings" {
    const allocator = std.testing.allocator;
    const strs = [_][]const u8{ "a", "b", "c" };
    const result = try join_strings(allocator, &strs, ":");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("a:b:c", result);
}

test "intify" {
    const allocator = std.testing.allocator;
    const strs = [_][]const u8{ "1", "2", "3" };
    const result = try intify(allocator, &strs);
    defer allocator.free(result);
    try std.testing.expectEqualSlices(i32, &[_]i32{ 1, 2, 3 }, result);
}

test "python_split" {
    const allocator = std.testing.allocator;
    var tokens = try python_split(allocator, "  foo  bar  baz  ");
    defer {
        for (tokens.items) |t| allocator.free(t);
        tokens.deinit();
    }
    try std.testing.expectEqual(@as(usize, 3), tokens.items.len);
    try std.testing.expectEqualStrings("foo", tokens.items[0]);
}
