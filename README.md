# gem-repair

A RubyGems plugin for the broken C extensions you get when several rubies share one `GEM_HOME`.

## The problem

Version managers such as mise and rbenv let every ruby point at the same `GEM_HOME`, which saves installing the same gems once per ruby. C extensions do not survive that, because `gem install` compiles them only for the ruby that runs it.

Install `bcrypt` under ruby 3.3 into a shared `GEM_HOME`:

```console
$ GEM_HOME=/tmp/shared mise x ruby@3.3 -- gem install bcrypt
Building native extensions. This could take a while...
Successfully installed bcrypt-3.1.22
```

RubyGems writes the compiled extension to two places:

```
/tmp/shared/extensions/arm64-darwin-27/3.3.0/bcrypt-3.1.22/bcrypt_ext.bundle
/tmp/shared/gems/bcrypt-3.1.22/lib/bcrypt_ext.bundle
```

The first is per-ABI and belongs to ruby 3.3 alone. The second is a copy inside the gem's own `lib`, which every ruby shares. Each one breaks the other rubies in a different way.

### The gem is ignored

Ruby 3.4 looks for `extensions/arm64-darwin-27/3.4.0/`, does not find it, and drops the gem off the load path:

```console
$ GEM_HOME=/tmp/shared mise x ruby@3.4 -- ruby -e 'require "bcrypt"'
Ignoring bcrypt-3.1.22 because its extensions are not built. Try: gem pristine bcrypt --version 3.1.22
-e:1:in 'Kernel#require': cannot load such file -- bcrypt (LoadError)
```

### The copy in lib shadows the right one

Build the extension for 3.4 as well and the gem is no longer ignored. It still fails, because `lib` comes before `extensions/` on the load path, so 3.4 loads the object file linked against ruby 3.3:

```console
$ GEM_HOME=/tmp/shared mise x ruby@3.4 -- ruby -e 'require "bcrypt"'
-e:1:in 'Kernel#require': linked to incompatible /opt/rubies/3.3/lib/libruby.3.3.dylib - /tmp/shared/gems/bcrypt-3.1.22/lib/bcrypt_ext.bundle (LoadError)
```

Running `gem pristine --all` under each ruby in turn does not settle this. The last ruby to run it wins the copy in `lib` and breaks the others, and the next `gem install` starts the cycle again.

## What this plugin does

It covers the problem from three directions.

1. After every install it deletes the extension copy from the gem's `lib`, so no ruby can load another ruby's object file.
2. After every install it builds the extensions of the gem just installed for the other rubies sharing the `GEM_HOME`, so switching rubies does not leave the gem ignored.
3. `gem repair` does both across a `GEM_HOME` that is already broken.

With the plugin installed, one `gem install` under 3.3 leaves 3.4 working:

```console
$ GEM_HOME=/tmp/shared GEM_REPAIR_RUBIES=3.4 mise x ruby@3.3 -- gem install bcrypt
Building native extensions. This could take a while...
Removed /tmp/shared/gems/bcrypt-3.1.22/lib/bcrypt_ext.bundle
Built bcrypt-3.1.22 extensions for 3.4
Successfully installed bcrypt-3.1.22

$ GEM_HOME=/tmp/shared mise x ruby@3.4 -- ruby -e 'require "bcrypt"; puts BCrypt::Password.create("x")'
$2a$12$ko9GRH9PfrJSkF4yD4xXA.BZILRlBpCyOVTnB2XvkYYo5r/cT5FOi
```

## Installation

```sh
gem install gem-repair
```

Install it into the shared `GEM_HOME`, not into a per-ruby one. RubyGems loads plugins from `GEM_PATH`, so one copy there is what makes every ruby run the hook.

Rubies below 2.7 load the plugin too. They get the `gem repair` command but not the install hook.

## Repairing a GEM_HOME you already broke

```sh
gem repair
```

It sweeps the extension copies out of `lib`, finds every gem whose extensions are missing for the running ruby, and reinstalls them. Reinstalling runs the install hooks, so the fan-out to the other rubies happens here as well.

```console
$ gem repair -j 2
Searching for gems with missing extensions...
Removed /tmp/shared/gems/bcrypt-3.1.22/lib/bcrypt_ext.bundle
Removed /tmp/shared/gems/msgpack-1.8.4/lib/msgpack/msgpack.bundle
Found 2 gem(s) to repair: msgpack-1.8.4, bcrypt-3.1.22
Repairing gems using 2 parallel threads...
Repairing msgpack-1.8.4...
Repairing bcrypt-3.1.22...
Successfully repaired bcrypt-3.1.22 to /tmp/shared
Successfully repaired msgpack-1.8.4 to /tmp/shared
Gem repair process complete.
```

Start with `-n` if you want to see the plan first.

| Option | Effect |
| --- | --- |
| `-j N`, `--jobs N` | Number of parallel threads (default: 4) |
| `--prune` | Uninstall gems whose extensions are still missing for the running ruby after repair, even when the reinstall itself failed |
| `--aggressive-sweep` | Also remove the `test`, `spec`, `features` and `tmp` directories of every gem |
| `-n`, `--dry-run` | Show what would be removed, repaired or uninstalled without changing anything |

## How the sweep picks its targets

RubyGems 3.6 added the `install_extension_in_lib` gemrc setting to skip the copy into `lib`, but it is still on by default, and gems installed by an older RubyGems already have the copy. So the sweep cannot be retired yet.

Only files that also exist under `extensions/` are removed, which is how a copy is told apart from an object file the gem shipped itself. Copies under versioned directories such as `lib/3.3/`, which precompiled gems use to carry one extension per ABI, are left alone.

## How the fan-out finds the other rubies

Rubies are looked up under the install roots of mise and rbenv:

| Variable | Default | Rubies |
| --- | --- | --- |
| `MISE_DATA_DIR` | `$XDG_DATA_HOME/mise` | `installs/ruby/*` |
| `RBENV_ROOT` | `~/.rbenv` | `versions/*` |

`GEM_REPAIR_RUBIES` narrows the targets to a comma-separated list of version names, for example `GEM_REPAIR_RUBIES=3.3-dev,3.4-dev`. Set it to an empty string to turn the fan-out off. That is worth doing if you keep dozens of rubies installed but only use a few.

JRuby, TruffleRuby, mruby and Rubinius installs are always skipped, as is a ruby whose version the gem does not support. The fan-out does not run inside `bundle install`, though the sweep still does. It only runs for a `GEM_HOME` outside the per-ABI directories the running ruby keeps to itself, `Gem.default_dir` and `Gem.user_dir`, since nothing else reads those.

## Migrating from gem-sweep

This replaces the `gem sweep` command and the install hook of the gem-sweep plugin. Uninstall it so the two hooks do not run side by side:

```sh
gem uninstall gem-sweep
```

`gem sweep --missing-extensions` becomes `gem repair --prune`, `gem sweep --aggressive` becomes `gem repair --aggressive-sweep`, and `gem sweep -n` becomes `gem repair -n`.

## Development

After checking out the repo, run `bundle install` to install dependencies. Then, you can run `rake test` to run the tests.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `gem-repair.gemspec`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [a configured gem server](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/hsbt/gem-repair.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
