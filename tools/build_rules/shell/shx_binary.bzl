# Author: Benjamin Staffin <benley@gmail.com>
"""shx: nifty self-extracting shell script executables

shx files are like pex binaries, but for bash scripts instead of python apps.
Internally, they are just ZIP files with special shell script header.  You can
use shx archives to wrap and deploy any type of files; just be mindful of how
long the unzip operation will take at startup if it's something you expect to
launch frequently.

When you add data dependencies to a shx_binary, they can be found at runtime in
`${RUNFILES}/` at the path where the build target is defined.  For example, if
you depend on `//ops/tools/foobla:foobla.pex`, at runtime that will be
`${RUNFILES}/ops/tools/foobla/foobla.pex`.

Example usage:

```python
load("//tools/build_rules/shell:shx_binary.bzl", "shx_binary")

shx_binary(
    name = "demo",
    main = "demo.sh",
    deps = ["demolib.sh"],
    data = ["//third_party/py/zk_shell:zk_shell.pex"],
)
```

Assuming the above example lives in //tools/build_rules/shell, you can:

  * `bazel build //tools/build_rules/shell:demo` to quickly get a runnable
    script. This should work just like a bazel `sh_binary` target would.
  * `bazel build //toold/build_rules/shell:demo.shx` to build a deployable,
    standalone shx executable containing demo.sh and all of its dependencies.

Protip: if you're editing and debugging a script in progress, after you run
`bazel build` on it once, you can make changes to its source files (i.e. things
that don't require any build/compilation steps) and re-run the unpacked script
directly out of `bazel-bin` without rebuilding.
"""

def _pick_main_file(ctx):
  """Return a file to use as the script's entrypoint.

  This matches the behavior of main / srcs in native.py_binary.

  If the main attribute is set, use that.  Otherwise, look for a file in srcs
  whose name matches the rule.
  """
  if ctx.file.main:
    return ctx.file.main

  expected_filename = "%s.sh" % ctx.label.name
  for src in ctx.files.srcs:
    if src.basename == expected_filename:
      return src

  fail("Found no file in srcs named '%s', and main is also unset." %
       expected_filename)


def _dirname(f):
  return f.short_path.rpartition("/")[0]

def _shx_binary(ctx):
  files = set(ctx.files.srcs + ctx.files.main +
              ctx.files.data + ctx.files.deps)

  # For parity with native.sh_binary, include the script entrypoint in the
  # runfiles tree:
  files += [ctx.outputs.executable]

  for dep in ctx.attr.deps:
    files += dep.default_runfiles.files

  runfiles = ctx.runfiles(
      transitive_files = files,
      collect_default = True,
  )

  main_file = _pick_main_file(ctx)

  # GenMain is a separate action so you can build it by itself
  ctx.template_action(
      template = ctx.file._main_stub_template,
      output = ctx.outputs.executable,
      substitutions = {
          "%{main}": main_file.short_path,
          "%{workspace_name}": ctx.workspace_name,
      },
  )
  ctx.action(
      mnemonic = "MakeZip",
      inputs = list(runfiles.files) + [ctx.outputs.executable],
      outputs = [ctx.outputs.zip],
      command = "\n".join(
          [
              'set -e',  # You'd think this would be the default...
              'TMPDIR=$(mktemp -d ./shx.XXXXXX)',
              'trap "rm -rf ${TMPDIR}" EXIT',
              'NAME="%s"' % ctx.label.name,
              # mkdir in case NAME has slashes in it (yes, it can!)
              'mkdir -p $(dirname "${TMPDIR}/${NAME}")',
              'RUNFILES="${TMPDIR}/${NAME}.runfiles/%s"' % ctx.workspace_name,
              'ln -s "$PWD/%s" "${TMPDIR}/${NAME}"' % ctx.outputs.executable.path,
              'mkdir -p "${TMPDIR}/${NAME}.runfiles"'
          ] +
          [   # Make the runfiles symlink tree to zip up
              'mkdir -p "${RUNFILES}/%s";' % _dirname(f) +
              'ln -s "$PWD/%s" "${RUNFILES}/%s"' % (f.path, f.short_path)
              for f in runfiles.files
          ] +
          [   # Set a fixed mtime and atime for repeatable builds
              'find "$TMPDIR" -exec touch -t 198001010000.00 {} \;',
              '(cd "$TMPDIR"; zip --quiet -r "../%s" .)' % ctx.outputs.zip.path,
          ]
      ),
  )
  ctx.template_action(
      template = ctx.file._zip_header_template,
      output = ctx.outputs.zip_header,
      substitutions = {
          "%{main}": ctx.label.name,
      },
  )
  ctx.action(
      mnemonic = "MakeSelfExtractable",
      inputs = [ctx.outputs.zip_header, ctx.outputs.zip] + list(runfiles.files),
      outputs = [ctx.outputs.shx],
      command = "\n".join([
          'set -e',
          'cat "%s" "%s" > "%s"' % (
              ctx.outputs.zip_header.path,
              ctx.outputs.zip.path,
              ctx.outputs.shx.path),
          'zip -qA "%s"' % ctx.outputs.shx.path,
      ]),
  )
  return struct(
      files = set([ctx.outputs.executable]),
      runfiles = runfiles,
  )

shx_binary = rule(
    _shx_binary,
    executable = True,
    attrs = {
        "srcs": attr.label_list(
            allow_files = FileType([".sh", ".bash"]),
        ),
        "deps": attr.label_list(
            allow_files = FileType([".sh", ".bash"]),
        ),
        "data": attr.label_list(
            allow_files = True,
            cfg = "data",
        ),
        "main": attr.label(
            allow_files = FileType([".sh", ".bash"]),
            single_file = True,
        ),
        "_main_stub_template": attr.label(
            default = Label("//tools/build_rules/shell:main_stub.sh.tmpl"),
            allow_files = True,
            single_file = True,
        ),
        "_zip_header_template": attr.label(
            default = Label("//tools/build_rules/shell:zip_header.sh.tmpl"),
            allow_files = True,
            single_file = True,
        ),
    },
    outputs = {
        "zip": "%{name}.zip",
        "zip_header": "%{name}.zip_header",
        "shx": "%{name}.shx",
    },
)
"""Deployable self-extracting shell scripts.

This rule's default output is identical to that of Bazel's built-in sh_binary,
but if you ask bazel to build <name>.shx, it will produce a self-extracting
binary that can be deployed without a separate runfiles tree.
"""
