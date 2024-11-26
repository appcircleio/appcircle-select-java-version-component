# Appcircle Select Java Version

This step switches to the selected Java version during the build process. 

If your runner is self-hosted, ensure that the selected Java version is available in your environment. If not, you must install the required version before this step.

## Required Input Variables

- `$AC_SELECTED_JAVA_VERSION`: Select the Java version to switch to. If the selected version is not available on the runner, an error will occur. [Check available Java versions for your runner](https://docs.appcircle.io/infrastructure/android-build-infrastructure#java-version).
