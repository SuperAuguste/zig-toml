# zig-toml

![haze forced me to make this README](https://img.shields.io/static/v1?label=haze&message=forced%20me%20to%20make%20this%20README&color=F7A41D)

`zig-toml` is a TOML library for Zig (duh).

<!-- omit in toc -->
## Table Of Contents
- [Installation](#installation)
  - [Cloning](#cloning)
  - [Adding as Submodule](#adding-as-submodule)
- [Usage](#usage)

## Installation

Installing `zig-toml` is pretty simple. First, ensure that you have [the latest zig build available](https://ziglang.org/download/).
Then, pick a method listed below that you like, and try it out!

### Cloning

```bash
# in your directory of choice:
git clone --recurse-submodules https://github.com/haze/zig-toml

# Now you can TOML away!!
```

### Adding as Submodule

```bash
# in your git repo of choice:
git submodule add https://github.com/haze/zig-toml

# Now you can TOML away, but in submodule form!!
```

## Usage

A great way to get started with `zig-toml` is to look at [the tests](https://github.com/haze/zig-toml/blob/master/src/test.zig)!

In essence, `zig-toml` is like `std.json` in the sense that you can use `x.?.String` or `x.?.Array` to query for values. The only main differences are that `x.?.Object`
becomes `x.?.SubTable`, and opening a TOML file is done using `try toml.Table.fromString(allocator, toml_data)`.
