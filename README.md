# kettle-jem-appraisals

🍲 Auto-generate Appraisal matrices for kettle-jem managed gems.

## Synopsis

Scaffolds tier1/tier2 gem lists from gemspec analysis, resolves version
spreads from RubyGems API data per mode (major/minor/minor-minmax/semver),
generates modular gemfiles and Appraisals files.

## Installation

```sh
gem install kettle-jem-appraisals
```

## Basic Usage

From inside your gem's repository:

```sh
# Scaffold initial tier1/tier2 from gemspec
kettle-jem-appraisals --scaffold

# Edit .kettle-jem.yml to arrange tiers, then resolve
kettle-jem-appraisals --resolve
```

## License

AGPL-3.0-only
