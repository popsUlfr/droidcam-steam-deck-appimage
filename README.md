# DroidCam AppImage for the Steam Deck

- https://github.com/dev47apps/droidcam
- https://play.google.com/store/apps/details?id=com.dev47apps.droidcam
- https://play.google.com/store/apps/details?id=com.dev47apps.droidcamx

It bundles the `v4l2loopback-dc` kernel module for the known SteamOS kernel versions (stable, beta) and tries to be smart about loading the module.

The goal is to be as easy as possible to use droidcam on the Steam Deck.

# How it works

Before launching the app it will try to load the `v4l2loopback-dc` kernel module if it's not already loaded.
It will need root credentials to do so and use an appropriate or manually set `SUDO_ASKPASS` helper for this.
It will merge the currently running kernel's module folder with the one shipping in the AppImage using `overlayfs` and attempt to load the shipped kernel module that way.

# droidcam-cli

To access the droidcam cli tool you can simply rename or create a link to the AppImage so that it starts with `droidcam-cli`.

```sh
ln -s DroidCam-*-x86_64_SteamDeck.AppImage droidcam-cli
```

# Build

Requires podman or docker.
It will use the archlinux image converted into a SteamOS base to build the kernel module `v4l2loopback-dc`.

The DroidCam gui application is built in ubuntu 20.04.

```sh
./build.sh
```

The resulting AppImage will appear as `DroidCam-*-x86_64_SteamDeck.AppImage`
