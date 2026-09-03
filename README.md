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
1. Find all installed gems that are missing their compiled C extensions.
2. Attempt to reinstall these gems using multiple threads.

## Building for other rubies on install

Several rubies can share one `GEM_HOME`, but `gem install` only compiles extensions for the ruby that runs it. The plugin hooks `Gem.post_install` and builds the extensions of the gem just installed for every other ruby it can find, so switching rubies does not leave the gem ignored with "extensions are not built".

Rubies are looked up under the install roots of mise and rbenv:

| Variable | Default | Rubies |
| --- | --- | --- |
| `MISE_DATA_DIR` | `$XDG_DATA_HOME/mise` | `installs/ruby/*` |
| `RBENV_ROOT` | `~/.rbenv` | `versions/*` |

`GEM_REPAIR_RUBIES` narrows the targets to a comma-separated list of version names, for example `GEM_REPAIR_RUBIES=3.3-dev,3.4-dev`. Set it to an empty string to turn the fan-out off. JRuby, TruffleRuby, mruby and Rubinius installs are always skipped, as is a ruby whose version the gem does not support. The fan-out does not run inside `bundle install`. It only runs for a `GEM_HOME` outside the per-ABI directories the running ruby keeps to itself, `Gem.default_dir` and `Gem.user_dir`. The hook also fires when `gem repair` or `gem pristine` reinstalls a gem.

## Development

After checking out the repo, run `bundle install` to install dependencies. Then, you can run `rake test` to run the tests.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `gem-repair.gemspec`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [a configured gem server](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/hsbt/gem-repare.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
