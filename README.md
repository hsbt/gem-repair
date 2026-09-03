# gem-repair

A RubyGems plugin to repair gems with missing extensions.

## Installation

Build and install the gem locally:

```sh
gem build gem-repair.gemspec
gem install ./gem-repair-0.1.0.gem
```

Or, if you are managing it within a Bundler context, add it to your Gemfile:

```ruby
gem 'gem-repair', path: './labs/gem-repair' # Adjust path as necessary
```

## Usage

After installation, the `gem repair` command will be available:

```sh
gem repair
```

You can also specify the number of parallel threads to use:

```sh
gem repair -j 8  # Use 8 threads
gem repair --jobs 2  # Use 2 threads
```

This command will:
1. Remove the copies of built extensions left in the `lib` directory of every gem with extensions (see below).
2. Find all installed gems that are missing their compiled C extensions.
3. Attempt to reinstall these gems using multiple threads.

Options:

| Option | Effect |
| --- | --- |
| `-j N`, `--jobs N` | Number of parallel threads (default: 4) |
| `--prune` | Uninstall gems whose extensions are still missing for the running ruby after repair, even when the reinstall itself failed |

| `-n`, `--dry-run` | Show what would be removed, repaired or uninstalled without changing anything |

## Removing extension copies from lib

RubyGems copies each built extension into the gem's `lib` directory as well as the per-ruby `extensions/<platform>/<abi>/` directory. RubyGems 3.6 added the `install_extension_in_lib` gemrc setting to skip that copy, but it stays on by default. `lib` comes first on the load path, so every other ruby sharing the `GEM_HOME` loads the copy built for the installing ruby and fails with a `LoadError`. The plugin removes those copies right after each install and on every `gem repair`. Copies under versioned directories such as `lib/3.3/`, which precompiled gems use to ship one extension per ABI, are left alone.

### Migrating from gem-sweep

This replaces the `gem sweep` command and the install hook of the gem-sweep plugin. Uninstall it so the two hooks do not run side by side:

```sh
gem uninstall gem-sweep
```

`gem sweep --missing-extensions` becomes `gem repair --prune`, and `gem sweep -n` becomes `gem repair -n`.

## Building for other rubies on install

Several rubies can share one `GEM_HOME`, but `gem install` only compiles extensions for the ruby that runs it. The plugin hooks `Gem.post_install` and builds the extensions of the gem just installed for every other ruby it can find, so switching rubies does not leave the gem ignored with "extensions are not built".

Rubies are looked up under the install roots of mise and rbenv:

| Variable | Default | Rubies |
| --- | --- | --- |
| `MISE_DATA_DIR` | `$XDG_DATA_HOME/mise` | `installs/ruby/*` |
| `RBENV_ROOT` | `~/.rbenv` | `versions/*` |

`GEM_REPAIR_RUBIES` narrows the targets to a comma-separated list of version names, for example `GEM_REPAIR_RUBIES=3.3-dev,3.4-dev`. Set it to an empty string to turn the fan-out off. JRuby, TruffleRuby, mruby and Rubinius installs are always skipped, as is a ruby whose version the gem does not support. The fan-out does not run inside `bundle install`, though the sweep still does. It only runs for a `GEM_HOME` outside the per-ABI directories the running ruby keeps to itself, `Gem.default_dir` and `Gem.user_dir`. The hook also fires when `gem repair` or `gem pristine` reinstalls a gem.

## Development

After checking out the repo, run `bundle install` to install dependencies. Then, you can run `rake test` to run the tests.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `gem-repair.gemspec`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [a configured gem server](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/hsbt/gem-repare.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
