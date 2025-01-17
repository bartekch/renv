
`_renv_status_running` <- FALSE

#' Report differences between lockfile and project library
#'
#' Report differences between the project's lockfile and the current state of
#' the project's library (if any).
#'
#' @inherit renv-params
#'
#' @param library The library paths. By default, the library paths associated
#'   with the requested project are used.
#'
#' @param sources Boolean; check that each of the recorded packages have a
#'   known installation source? If a package has an unknown source, renv
#'   may be unable to restore it.
#'
#' @param cache Boolean; perform diagnostics on the global package cache?
#'   When `TRUE`, renv will validate that the packages installed into the
#'   cache are installed at the expected + proper locations, and validate the
#'   hashes used for those storage locations.
#'
#' @return This function is normally called for its side effects, but
#'   it invisibly returns a list containing the following components:
#'
#'   * `library`: packages in your library.
#'   * `lockfile`: packages in the lockfile.
#'   * `synchronized`: are the library and lockfile in sync?
#'
#' @export
#'
#' @example examples/examples-init.R
status <- function(project = NULL,
                   ...,
                   library = NULL,
                   lockfile = NULL,
                   sources = TRUE,
                   cache = FALSE)
{
  renv_scope_error_handler()
  renv_dots_check(...)

  renv_snapshot_auto_suppress_next()
  renv_scope_options(renv.prompt.enabled = FALSE)

  project <- renv_project_resolve(project)
  renv_project_lock(project = project)

  libpaths <- renv_libpaths_resolve(library)
  lockpath <- lockfile %||% renv_lockfile_path(project)

  invisible(renv_status_impl(project, libpaths, lockpath, sources, cache))
}

renv_status_impl <- function(project, libpaths, lockpath, sources, cache) {

  default <- list(library = list(), lockfile = list(), synchronized = FALSE)

  # check to see if we've initialized this project
  if (!renv_project_initialized(project)) {
    writef("* This project has not yet been initialized.")
    return(default)
  }

  # mark status as running
  `_renv_status_running` <<- TRUE
  defer(`_renv_status_running` <<- FALSE)

  # check for existing lockfile, library
  ok <-
    renv_status_check_missing_library(project, libpaths) &&
    renv_status_check_missing_lockfile(project, lockpath)

  if (!ok)
    return(default)

  # get all dependencies, including transitive
  dependencies <- renv_snapshot_dependencies(project)
  packages <- sort(union(dependencies, "renv"))
  paths <- renv_package_dependencies(packages, project = project)
  packages <- as.character(names(paths))

  # get lockfile records
  lockfile <- renv_lockfile_records(renv_lockfile_read(lockpath))

  # get library records
  library <- renv_snapshot_libpaths(libpaths = libpaths, project = project)

  # remove ignored packages
  ignored <- c(
    renv_project_ignored_packages(project),
    renv_packages_base(),
    if (renv_tests_running()) "renv"
  )
  packages <- setdiff(packages, ignored)
  lockfile <- exclude(lockfile, ignored)
  library <- exclude(library, ignored)

  synchronized <- renv_status_check_synchronized(
    project      = project,
    lockfile     = lockfile,
    library      = library,
    packages     = packages
  )

  if (sources) {
    synchronized <- synchronized &&
      renv_status_check_unknown_sources(project, lockfile)
  }

  if (cache)
    renv_status_check_cache(project)

  if (synchronized)
    writef("* The project is already synchronized with the lockfile.")

  list(
    library      = library,
    lockfile     = lockfile,
    synchronized = synchronized
  )

}

renv_status_check_missing_lockfile <- function(project, lockpath) {

  if (file.exists(lockpath))
    return(TRUE)

  if (identical(lockpath, renv_lockfile_path(project)))
    writef("* This project has not yet been snapshotted -- 'renv.lock' does not exist.")
  else
    writef("* Lockfile %s does not exist.", renv_path_pretty(lockpath))

  FALSE

}

renv_status_check_missing_library <- function(project, libpaths) {

  projlib <- nth(libpaths, 1L)
  if (file.exists(projlib))
    return(TRUE)

  if (identical(projlib, renv_paths_library(project = project)))
    writef("* This project's private library is empty or does not exist.")
  else
    writef("* Library %s is empty or does not exist.", renv_path_pretty(projlib))

  FALSE

}

renv_status_check_unknown_sources <- function(project, lockfile) {
  renv_check_unknown_source(lockfile, project)
}

renv_status_check_synchronized <- function(project,
                                           lockfile,
                                           library,
                                           packages)
{
  # projects will implicitly depend on BiocManager if any Bioconductor
  # packages are in use
  sources <- extract_chr(library, "Source")
  if ("Bioconductor" %in% sources)
    packages <- unique(c(packages, "BiocManager"))

  # missing dependencies -------------------------------------------------------
  # Must return early because `packages` will be incomplete making later
  # reports confusing
  missing <- setdiff(packages, names(library))
  if (length(missing)) {

    lockmsg <- "The following packages are recorded in the lockfile, but not installed:"
    usedmsg <- "The following packages are used in this project, but not installed:"
    restoremsg <- "Use `renv::restore()` to restore the packages recorded in the lockfile."
    installmsg <- "Consider installing these packages -- for example, with `renv::install()`."
    statusmsg <- "Use `renv::status()` afterwards to re-assess the project state."

    # if these packages are in the lockfile, report those records
    if (all(missing %in% names(lockfile))) {

      records <- keep(lockfile, missing)
      renv_pretty_print_records(
        records,
        preamble  = lockmsg,
        postamble = restoremsg
      )

      return(FALSE)

    }

    # otherwise, try to report intelligently
    postamble <- if (any(missing %in% names(lockfile))) {
      c(restoremsg, statusmsg)
    } else {
      c(installmsg, statusmsg)
    }

    renv_pretty_print(
      missing,
      preamble  = usedmsg,
      postamble = postamble
    )

    return(FALSE)

  }

  # flag set to FALSE if any of the below checks report out-of-sync
  ok <- TRUE

  # not installed/recorded/used ------------------------------------------------
  records <- lockfile %>%
    exclude(names(library)) %>%
    keep(packages)

  if (length(records)) {

    renv_pretty_print_records(
      records,
      "The following package(s) are recorded in the lockfile, but not installed:",
      "Use `renv::restore()` to install these packages."
    )

    ok <- FALSE

  }

  # installed/not recorded/used ------------------------------------------------
  records <- library %>%
    exclude(names(lockfile)) %>%
    keep(packages)

  if (length(records)) {

    renv_pretty_print_records(
      records,
      "The following package(s) are installed, but not recorded in the lockfile:",
      "Use `renv::snapshot()` to add these packages to the lockfile."
    )

    ok <- FALSE

  }

  # */recorded/not used --------------------------------------------------------
  records <- lockfile %>% exclude(packages)
  if (length(records)) {

    renv_pretty_print_records(
      records,
      preamble =
        "The following packages are recorded in the lockfile, but do not appear to be used in this project:",
      postamble =
        "Use `renv::snapshot()` if you'd like to remove these packages from the lockfile."
    )

    ok <- FALSE

  }

  # */not recorded/not used ----------------------------------------------------
  # No action; it's okay if some auxiliary packages are installed.

  # other changes, i.e. different version/source -------------------------------
  actions <- renv_lockfile_diff_packages(lockfile, library)
  rest <- c("upgrade", "downgrade", "crossgrade")
  if (any(rest %in% actions)) {

    matches <- actions[actions %in% rest]

    rlock <- renv_lockfile_records(lockfile)[names(matches)]
    rlibs <- renv_lockfile_records(library)[names(matches)]

    renv_pretty_print_records_pair(
      rlock,
      rlibs,
      preamble = "The following package(s) are out of sync [lockfile -> library]:",
      postamble = c(
        "Use `renv::snapshot()` to save the state of your library to the lockfile.",
        "Use `renv::restore()` to restore your library from the lockfile."
      )
    )

    ok <- FALSE

  }

  ok
}

renv_status_check_cache <- function(project) {

  if (renv_cache_config_enabled(project = project))
    renv_cache_diagnose()

}

