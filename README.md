Lambdapi, a proof assistant based on the λΠ-calculus modulo rewriting [![Gitter][gitter-badge]][gitter-link] [![Matrix][matrix-badge]][matrix-link]
=====================================================================

[User Manual](https://lambdapi.readthedocs.io)
-------------

Issues can be reported on the following
[issue tracker](https://github.com/Deducteam/lambdapi/issues).

Questions can be asked on the following
[forum](https://github.com/Deducteam/lambdapi/discussions).

Operating systems
-----------------

Lambdapi requires a Unix-like system. It should work on Linux as well as on
MacOS. It might be possible to make it work on Windows too with Cygwin or
"bash on Windows".

Installation via Opam
---------------------

Lambdapi is under active development. A new version of the `lambdapi`
[Opam](http://opam.ocaml.org/) package will be released soon,
when the development will have reached a
more stable point. For now, we advise you to pin the development
repository to get the latest development version:
```bash
opam pin add lambdapi https://github.com/Deducteam/lambdapi.git
opam install lambdapi # install emacs and vim support as well
```
For installing the VSCode extension, you need to get the sources (see below).

The installation gives you:

* a main executable named ``lambdapi`` in your ``PATH``
* an OCaml library called ``lambdapi.core`` (system internals)
* an OCaml library called ``lambdapi.pure`` (pure interface)
* an OCaml library called ``lambdapi.lsp`` (LSP server)
* a ``lambdapi`` mode for ``Vim`` (optional)
* a ``lambdapi`` mode for ``emacs`` (optional)

Compilation from the sources
----------------------------

You can get the sources using `git` as follows:
```bash
git clone https://github.com/Deducteam/lambdapi.git
```

Dependencies are described in `lambdapi.opam`. For running tests, one
also needs [alcotest](https://github.com/mirage/alcotest) and
[alt-ergo](https://alt-ergo.ocamlpro.com/). For building the source
code documentation, one needs
[odoc](https://github.com/ocaml/odoc). For building the User Manual,
see `docs/README.md`.

**Note on Why3:** the command `why3 config detect`
must be run to make Why3 know the available provers.

Using Opam, a suitable OCaml environment can be setup as follows:
```bash
opam switch 4.11.1
opam install dune bindlib timed menhir pratter yojson cmdliner why3 alcotest alt-ergo odoc
why3 config detect
```

To compile Lambdapi, just run the command `make` in the source directory.
This produces the `_build/install/default/bin/lambdapi` binary.
Use the `--help` option for more information. Other make targets are:

```bash
make                        # Build lambdapi
make doc                    # Build the Sphinx documentation
make odoc                   # Build the source code documentation
make install                # Install lambdapi
make install_emacs          # Install emacs mode
make install_vim            # Install vim support
make vscode                 # Install vscode extension
```

**Note:** you can run `lambdapi` without installing it with `dune exec -- lambdapi`.

**Note:** the starting file of the source code html documentation is
`_build/default/_doc/_html/lambdapi/index.html`.

The following commands can be used for cleaning up the repository:
```bash
make clean     # Removes files generated by OCaml.
make distclean # Same as clean, but also removes library checking files.
make fullclean # Same as distclean, but also removes downloaded libraries.
```

[gitter-badge]: https://badges.gitter.im/Deducteam/lambdapi.svg
[gitter-link]: https://gitter.im/Deducteam/lambdapi
[matrix-badge]: http://strk.kbt.io/tmp/matrix_badge.svg
[matrix-link]: https://riot.im/app/#/room/#lambdapi:matrix.org
