# Appcircle Select Java Version

This step switches to the selected Java version during the build process.

The step points the SDKMAN `current` Java link to the selected version and sets `JAVA_HOME` for the next steps. It does not call `sdk`, so it needs no internet access and works on air-gapped runners.

If your runner is self-hosted, ensure that the selected Java version is available in your runner environment. If not, you must install the required version before this step.

## Required Input Variables

- `$AC_SELECTED_JAVA_VERSION`: Select the Java version to switch to. If the selected version is not available on the runner, an error will occur. Check available Java versions for the Appcircle cloud-hosted runners [here](https://docs.appcircle.io/infrastructure/android-build-infrastructure#java-version).

## Running tests

Requires [RSpec](https://rspec.info) gem and Ruby standard library (Coverage). No Gemfile or Bundler needed.

```bash
ruby test/test_main.rb
```

A coverage report is printed at the end of each run.
