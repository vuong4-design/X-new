# AltList setup (build from source)

AltList does not provide a prebuilt framework download, so the setup script builds
the framework from source and installs the outputs into Theos. The script will use
`xcodebuild` when an Xcode project/workspace is present, or fall back to
`make framework` when the repo ships a Theos Makefile (falling back to a
default `make` with `SUBPROJECTS=` if that target is unavailable).

## Steps

1. Ensure Xcode and the command line tools are installed on the build machine.
2. Run the setup script as usual:

   ```bash
   bash scripts/setup_altlist.sh
   ```

The script clones the AltList repository, builds the framework (via `xcodebuild`
or `make`), and then copies the resulting framework and headers into Theos.
