#' Check if you have a development environment installed.
#'
#' Thanks to the suggestion of Simon Urbanek.
#'
#' @return TRUE if your development environment is correctly set up, otherwise
#'   returns an error.
#' @export
#' @examples
#' has_devel()
has_devel <- function() {
  foo_path <- file.path(tempdir(), "foo.c")

  cat("void foo(int *bar) { *bar=1; }\n", file = foo_path)
  on.exit(unlink(foo_path))

  R("CMD SHLIB foo.c", tempdir())
  dylib <- file.path(tempdir(), paste("foo", .Platform$dynlib.ext, sep=''))
  on.exit(unlink(dylib), add = TRUE)

  dll <- dyn.load(dylib)
  on.exit(dyn.unload(dylib), add = TRUE)

  stopifnot(.C(dll$foo, 0L)[[1]] == 1L)
  TRUE
}

check_build_tools <- function(pkg = ".") {
  pkg <- as.package(pkg)
  if (!file.exists(file.path(pkg$path, "src"))) return(TRUE)

  check <- getOption("buildtools.check", NULL)
  if (!is.null(check)) {
    check("Installing R package from source")
  } else {
    # Outside of Rstudio and don't have good heuristic
    TRUE
  }
}
