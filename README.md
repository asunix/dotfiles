# dotfiles

**Table of Contents**

<!-- toc -->

- [About](#about)
  * [Installing](#installing)
  * [Customizing](#customizing)
- [Resources](#resources)
- [Contributing](#contributing)
  * [Running the tests](#running-the-tests)
- [Acknowledgments](#acknowledgments)

<!-- tocstop -->

## About

### Installing

```console
$ make
```

This will create symlinks from this repo to your home folder.

### Customizing

Save env vars, etc in a `.extra` file, that looks something like
this:

```bash
###
### Git credentials
###

GIT_AUTHOR_NAME="Your Name"
GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
git config --global user.name "$GIT_AUTHOR_NAME"
GIT_AUTHOR_EMAIL="email@you.com"
GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
git config --global user.email "$GIT_AUTHOR_EMAIL"
GH_USER="nickname"
git config --global github.user "$GH_USER"

```

## Resources

## Contributing

### Running the tests

The tests use [shellcheck](https://github.com/koalaman/shellcheck). You don't
need to install anything. They run in a container.

```console
$ make test
```

## Acknowledgments

Many thanks to [Jessie Frazelle](https://github.com/jessfraz) for sharing her talent and other people from the github community.
