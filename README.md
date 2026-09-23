# Monday Bash Bang

<p align="center">
  <a href="https://github.com/OttoM1/Monday-bash-bang">
    <img src="monday-bash-bang.jpg" alt="Monday Bash Bang" width="100%">
  </a>
</p>

[![MIT](https://img.shields.io/badge/MIT-success?labelColor=2B2D42)](LICENSE)
[![Bash](https://img.shields.io/badge/Bash-3.2%2B-339933?labelColor=2B2D42)](https://www.gnu.org/software/bash/)
[![Expo](https://img.shields.io/badge/Expo-compatible-000020?labelColor=2B2D42&logo=expo&logoColor=white)](https://expo.dev)
[![CLI](https://img.shields.io/badge/interface-shell-5D11A9?labelColor=2B2D42)](./_until-green.sh)

bash scripts i actually use (don't recommend to use this as is, inside production/commercial projects).
individual files, copy whatever you like.
note: the `_hulk-smash.sh` needs `_zombie.sh` and `_until-green.sh` alongside for it to work.

## Navigate to:

- [\_until-green.sh](#_until-greensh-._until-greensh)
  - [Quick breakdown](#quick-breakdown)
  - [Put `_until-green.sh` in your project?](#put-_until-greensh-in-your-project)
- [\_zombie.sh](#_zombiesh-._zombiesh)
  - [Quick breakdown](#quick-breakdown-1)
  - [Put `_zombie.sh` in your project?](#put-_zombiesh-in-your-project)
- [\_hulk-smash.sh](#_hulk-smashsh-._hulk-smashsh)
  - [Quick breakdown](#quick-breakdown-2)
  - [Put `_hulk-smash.sh` in your project?](#put-_hulk-smashsh-in-your-project)
- [\_app.sh](#_appsh-._appsh)
  - [Install `_app.sh` ?](#install-_app)
- [License](#license)

## \_until-green.sh [`./_until-green.sh`](./_until-green.sh)

one command to get an automated pipeline to check current repo/branch/tree, fix vulnerabilities and get the simulator running in a react native / expo project.

### Quick breakdown:

runs `git remote -v`, `expo-doctor`, loops `expo install --fix` until every package matches your SDK, installs and then `npx expo start` starts the app.
the reason I do not recommend using this in a commercial project is because it will blindly install every package for you based on the --check flag.

### Put `_until-green.sh` in your project?

```bash
curl -o bash/_until-green.sh https://raw.githubusercontent.com/OttoM1/Monday-bash-bang/main/_until-green.sh
chmod +x ./bash/_until-green.sh # ./bash is just an example folder name, set it to whatever you want
```

then add `"go": "bash bash/_until-green.sh"` to your `package.json` scripts and run `npm run go`.

it should find the project root by walking up to the nearest `package.json`, so it doesn't care which folder you run it from.
(also reads your lockfile to pick npm/yarn/pnpm/bun)

## \_zombie.sh [`./_zombie.sh`](./_zombie.sh)

-

### Quick breakdown:

-

### Put `_zombie.sh` in your project?

```bash
curl -o bash/_zombie.sh https://raw.githubusercontent.com/OttoM1/Monday-bash-bang/main/_zombie.sh
chmod +x ./bash/_zombie.sh # ./bash is just an example folder name, set it to whatever you want
```

## \_hulk-smash.sh [`./_hulk-smash.sh`](./_hulk-smash.sh)

-

### Quick breakdown:

-

### Put `_hulk-smash.sh` in your project?

-

## \_app.sh [`./_app.sh`](./_app.sh)

-

### Install `_app.sh` ?

-

## License

[MIT](LICENSE)
