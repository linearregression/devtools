#' Check a package from CRAN.
#'
#' Internal function used to power \code{\link{revdep_check}()}.
#'
#' This function does not clean up after itself, but does work in a
#' session-specific temporary directory, so all files will be removed
#' when your current R session ends.
#'
#' @param pkgs Vector of package names - note that unlike other \pkg{devtools}
#'   functions this is the name of a CRAN package, not a path.
#' @param libpath Path to library to store dependencies packages - if you
#'   you're doing this a lot it's a good idea to pick a directory and stick
#'   with it so you don't have to download all the packages every time.
#' @param srcpath Path to directory to store source versions of dependent
#'   packages - again, this saves a lot of time because you don't need to
#'   redownload the packages every time you run the package.
#' @param bioconductor Include bioconductor packages in checking?
#' @param type binary Package type to test (source, mac.binary etc). Defaults
#'   to the same type as \code{\link{install.packages}()}.
#' @param threads Number of concurrent threads to use for checking.
#'   It defaults to the option \code{"Ncpus"} or \code{1} if unset.
#' @param check_dir Directory to store results.
#' @param revdep_pkg Optional name of a package for which this check is
#'   checking the reverse dependencies of. This is normally passed in from
#'   \code{\link{revdep_check}}, and is used only for logging.
#' @return invisible \code{TRUE} if successful and no ERRORs or WARNINGS.
#' @keywords internal
#' @export
check_cran <- function(pkgs, libpath = file.path(tempdir(), "R-lib"),
                       srcpath = libpath, bioconductor = FALSE,
                       type = getOption("pkgType"),
                       threads = getOption("Ncpus", 1),
                       check_dir = tempfile("check_cran"),
                       revdep_pkg = NULL) {

  stopifnot(is.character(pkgs))
  if (length(pkgs) == 0) return()

  rule("Checking ", length(pkgs), " CRAN packages", pad = "=")
  if (!file.exists(check_dir)) dir.create(check_dir)
  message("Results saved in ", check_dir)

  old <- options(warn = 1)
  on.exit(options(old), add = TRUE)

  rule("Installing dependencies")
  message("Determining available packages") # --------------------------------
  repos <- c(CRAN = "http://cran.rstudio.com/")
  message("Check with Bioconductor? ", bioconductor)
  if (bioconductor) {
    repos <- c(repos, BiocInstaller::biocinstallRepos())
  }
  available_src <- available_packages(repos, "source")
  available_bin <- available_packages(repos, type)

  # Create and use temporary library
  if (!file.exists(libpath)) dir.create(libpath)
  libpath <- normalizePath(libpath)

  # Add the temoporary library and remove on exit
  libpaths_orig <- set_libpaths(libpath)
  on.exit(.libPaths(libpaths_orig), add = TRUE)

  # Update/install dependencies ------------------------------------------------
  # Find all dependencies of reverse dependencies: need suggested packages for
  # the packages we're checking, but only Depends and Imports for their
  # dependencies.
  find_deps <- function(pkgs, ...) {
    all <- tools::package_dependencies(pkgs, db = available_bin, ...)
    unique(unlist(all))
  }
  deps <- find_deps(pkgs, "most")
  deps <- c(deps, find_deps(deps, c("Depends", "Imports"), recursive = TRUE))

  # Install if out of date or not already installed
  old <- old.packages(repos = repos, type = type,
    available = available_bin)[, "Package"]
  inst <- installed.packages()[, "Package"]
  to_install <- sort(union(
    intersect(deps, old),
    setdiff(deps, inst)
  ))

  known <- intersect(to_install, rownames(available_bin))
  unknown <- setdiff(to_install, rownames(available_bin))

  if (length(known) > 0) {
    message("Installing ", length(known), " missing/outdated dependencies")
    lapply(known, function(pkg) {
      message("Installing ", pkg)
      utils::install.packages(pkg, quiet = TRUE, repos = repos,
        dependencies = FALSE)
    })
  }
  if (length(unknown) > 0) {
    message("Skipping packages that lack binary version for this platform: \n",
      paste(unknown, collapse = ", "))
  }

  # Download and check each package, parsing output as we go.
  check_pkg <- function(i) {
    url <- package_url(pkgs[i], repos, available = available_src)
    if (length(url$url) == 0) {
      message("Skipping ", pkgs[i], ": can't find source")
      return(NULL)
    }
    local <- file.path(srcpath, url$name)

    if (!file.exists(local)) {
      message("Downloading ", pkgs[i])
      download.file(url$url, local, quiet = TRUE)
    }

    message("Checking ", pkgs[i])
    start_time <- Sys.time()
    try({
      check_r_cmd(
        local,
        cran = TRUE,
        check_version = FALSE,
        args = "--no-multiarch --no-manual --no-codoc",
        check_dir = check_dir,
        quiet = TRUE
      )
    }, silent = TRUE)
    end_time <- Sys.time()

    elapsed_time <- as.numeric(end_time - start_time, units = "secs")
    writeLines(
      sprintf("%d  %s  %.1f", i, pkgs[i], elapsed_time),
      file.path(check_dir, paste0(pkgs[i], ".Rcheck"), "check-time.txt")
    )

    NULL
  }

  rule("Checking packages")
  if (identical(as.integer(threads), 1L)) {
    lapply(seq_along(pkgs), check_pkg)
  } else {
    parallel::mclapply(seq_along(pkgs), check_pkg, mc.preschedule = FALSE,
      mc.cores = threads)
  }

  check_dir
}
