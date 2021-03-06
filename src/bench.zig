const toml = @import("toml.zig");
const benchmark = @import("zig-bench").benchmark;
const std = @import("std");
const t = std.testing;

test "benchmark" {
    const simpleKeyValue = "foo='123'";
    const exampleFile =
        \\# This is a TOML document. Boom.
        \\
        \\title = "TOML Example"
        \\
        \\[owner]
        \\name = "Tom Preston-Werner"
        \\organization = "GitHub"
        \\bio = "GitHub Cofounder & CEO\nLikes tater tots and beer."
        \\
        \\[database]
        \\server = "192.168.1.1"
        \\ports = [ 8001, 8001, 8002 ]
        \\connection_max = 5000
        \\enabled = true
        \\
        \\[servers]
        \\
        \\  # You can indent as you please. Tabs or spaces. TOML don't care.
        \\  [servers.alpha]
        \\  ip = "10.0.0.1"
        \\  dc = "eqdc10"
        \\
        \\  [servers.beta]
        \\  ip = "10.0.0.2"
        \\  dc = "eqdc10"
        \\  country = "中国" # This should be parsed as UTF-8
        \\
        \\[clients]
        \\data = [ ["gamma", "delta"], [1, 2] ] # just an update to make sure parsers support it
        \\
        \\# Line breaks are OK when inside arrays
        \\hosts = [
        \\  "alpha",
        \\  "omega"
        \\]
        \\
        \\# Products
        \\
        \\  [[products]]
        \\  name = "Hammer"
        \\  sku = 738594937
        \\
        \\  [[products]]
        \\  name = "Nail"
        \\  sku = 284758393
        \\  color = "gray"
    ;
    try benchmark(struct {
        pub const args = [_][]const u8{
            simpleKeyValue,
            exampleFile,
        };

        pub fn parseFile(file: []const u8) void {
            const table = toml.Parser.parse(std.debug.global_allocator, file) catch unreachable;
        }
    });
}
