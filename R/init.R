
#' Use renv in a project
#'
#' @description
#' Call `renv::init()` to start using renv in the current project. This will:
#'
#' 1. Set up project infrastructure (as described in [scaffold()]) including
#'    the project library and the `.Rprofile` that ensures renv will be
#'    used in all future sessions.
#'
#' 1. Discover the packages that you currently and install them into an
#'    project library (as described in [hydrate()]).
#'
#' 1. Create a lockfile that records the state of the project library so it
#'    can be restored by others (as described in [snapshot()]).
#'
#' 1. Restarts R (if running inside RStudio).
#'
#' If you call `init()` on a project that already uses renv, it will attempt
#' to do the right thing: it will restore the project library if it's missing,
#' or otherwise ask you what to do.
#'
#' # Repositories
#'
#' If the default \R repositories have not already been set, renv will use
#' the [Posit Public Package Manager](https://packagemanager.posit.co/) CRAN
#' mirror for package installation. The primary benefit to using this mirror is
#' that it can provide pre-built binaries for \R packages on a variety of
#' commonly-used Linux distributions. This behavior can be configured or
#' disabled if desired -- see the options in [renv::config()] for more details.
#'
#' @inherit renv-params
#'
#' @param project The project directory. When `NULL` (the default), the current
#'   working directory will be used. The \R working directory will be
#'   changed to match the requested project directory.
#'
#' @param settings A list of [settings] to be used with the newly-initialized
#'   project.
#'
#' @param bare Boolean; initialize the project without attempting to discover
#'   and install R package dependencies?
#'
#' @param force Boolean; force initialization? By default, renv will refuse
#'   to initialize the home directory as a project, to defend against accidental
#'   mis-usages of `init()`.
#'
#' @param repos The \R repositories to be used in this project.
#'   See **Repositories** for more details.
#'
#' @param bioconductor The version of Bioconductor to be used with this project.
#'   Setting this may be appropriate if renv is unable to determine that your
#'   project depends on a package normally available from Bioconductor. Set this
#'   to `TRUE` to use the default version of Bioconductor recommended by the
#'   BiocManager package.
#'
#' @param restart Boolean; attempt to restart the \R session after initializing
#'   the project? A session restart will be attempted if the `"restart"` \R
#'   option is set by the frontend embedding \R.
#'
#' @export
#'
#' @example examples/examples-init.R
init <- function(project = NULL,
                 ...,
                 profile      = NULL,
                 settings     = NULL,
                 bare         = FALSE,
                 force        = FALSE,
                 repos        = NULL,
                 bioconductor = NULL,
                 restart      = interactive())
{
  renv_consent_check()
  renv_scope_error_handler()
  renv_dots_check(...)

  project <- renv_path_normalize(project %||% getwd())
  renv_project_lock(project = project)

  # initialize profile
  if (!is.null(profile))
    renv_profile_set(profile)

  # normalize repos
  repos <- renv_repos_normalize(repos %||% renv_init_repos())
  options(repos = repos)

  # form path to lockfile, library
  library  <- renv_paths_library(project = project)
  lockfile <- renv_lockfile_path(project)

  # initialize bioconductor pieces
  biocver <- renv_init_bioconductor(bioconductor, project)
  if (!is.null(biocver)) {

    # make sure a Bioconductor package manager is installed
    renv_bioconductor_init(library = library)

    # retrieve bioconductor repositories appropriate for this project
    biocrepos <- renv_bioconductor_repos(project = project, version = biocver)
    options(repos = biocrepos)

    # notify user
    writef("* Using Bioconductor version '%s'.", biocver)
    settings[["bioconductor.version"]] <- biocver

  }


  # prepare and move into project directory
  renv_init_validate_project(project, force)
  renv_init_settings(project, settings)
  setwd(project)

  # be quiet in RStudio projects (as we will normally restart automatically)
  quiet <- !is.null(getOption("restart"))

  # for bare inits, just activate the project
  if (bare)
    return(renv_init_fini(project, profile, restart, quiet))

  # collect dependencies
  renv_dependencies_scope(project, action = "init")

  # determine appropriate action
  action <- renv_init_action(project, library, lockfile, bioconductor)
  cancel_if(empty(action) || identical(action, "cancel"))

  # activate library paths for this project
  libpaths <- renv_libpaths_activate(project = project)

  # perform the action
  if (action == "init") {
    renv_imbue_impl(project)
    hydrate(project = project, library = library, prompt = FALSE, report = FALSE)
    snapshot(project = project, library = libpaths, repos = repos, prompt = FALSE)
  } else if (action == "restore") {
    ensure_directory(library)
    restore(project = project, library = libpaths, prompt = FALSE)
  }

  # activate the newly-hydrated project
  renv_init_fini(project, profile, restart, quiet)

}

renv_init_fini <- function(project, profile, restart, quiet) {

  renv_activate_impl(
    project = project,
    profile = profile,
    version = renv_metadata_version(),
    restart = restart,
    quiet   = quiet
  )

  invisible(project)

}

renv_init_action <- function(project, library, lockfile, bioconductor) {

  # if the user has asked for bioconductor, treat this as a re-initialization
  if (!is.null(bioconductor))
    return("init")

  # figure out appropriate action
  case(

    # if both the library and lockfile exist, ask user for intended action
    file.exists(lockfile)
      ~ renv_init_action_conflict_lockfile(project, library, lockfile),

    # if a private library exists but no lockfile, ask whether we should use it
    file.exists(library)
      ~ renv_init_action_conflict_library(project, library, lockfile),

    # otherwise, we just want to initialize the project
    ~ "init"

  )

}

renv_init_action_conflict_lockfile <- function(project, library, lockfile) {

  if (!interactive())
    return("nothing")

  title <- "This project already has a lockfile. What would you like to do?"
  choices <- c(
    restore = "Restore the project from the lockfile.",
    init    = "Discard the lockfile and re-initialize the project.",
    nothing = "Activate the project without snapshotting or installing any packages.",
    cancel  = "Abort project initialization."
  )

  selection <- tryCatch(
    utils::select.list(choices, title = title, graphics = FALSE),
    interrupt = identity
  )

  if (inherits(selection, "interrupt"))
    return(NULL)

  names(selection)

}

renv_init_action_conflict_library <- function(project, library, lockfile) {

  if (!interactive())
    return("nothing")

  title <- "This project already has a private library. What would you like to do?"
  choices <- c(
    nothing = "Activate the project and use the existing library.",
    init    = "Re-initialize the project with a new library.",
    cancel  = "Abort project initialization."
  )

  selection <- tryCatch(
    utils::select.list(choices, title = title, graphics = FALSE),
    interrupt = identity
  )

  if (inherits(selection, "interrupt"))
    return(NULL)

  names(selection)

}

renv_init_validate_project <- function(project, force) {

  # allow all project directories when force = TRUE
  if (force)
    return(TRUE)

  # disallow attempts to initialize renv in the home directory
  home <- path.expand("~/")
  msg <- if (renv_file_same(project, home))
    "refusing to initialize project in home directory"
  else if (renv_path_within(home, project))
    sprintf("refusing to initialize project in directory '%s'", project)

  if (!is.null(msg)) {
    msg <- paste(msg, "-- use renv::init(force = TRUE) to override")
    stopf(msg)
  }

}

renv_init_settings <- function(project, settings) {

  defaults <- renv_settings_get(project)
  merged <- renv_settings_merge(defaults, settings)
  renv_settings_persist(project, merged)
  invisible(merged)

}

renv_init_bioconductor <- function(bioconductor, project) {

  # if we're re-initializing a project that appears to depend
  # on Bioconductor, then use the latest Bioconductor release
  if (is.null(bioconductor)) {
    lockpath <- renv_paths_lockfile(project = project)
    if (file.exists(lockpath)) {
      lockfile <- renv_lockfile_read(lockpath)
      bioconductor <- !is.null(lockfile$Bioconductor)
    }
  }

  # resolve bioconductor argument
  case(
    is.character(bioconductor)     ~ bioconductor,
    identical(bioconductor, TRUE)  ~ renv_bioconductor_version(project, refresh = TRUE),
    identical(bioconductor, FALSE) ~ NULL
  )

}

renv_init_repos <- function() {

  # if PPM is disabled, just use default repositories
  repos <- convert(getOption("repos"), "list")
  if (!renv_ppm_enabled())
    return(repos)

  enabled <- config$ppm.default()
  if (!enabled)
    return(repos)

  # if we're using the global CDN from RStudio, use PPM instead
  rstudio <- attr(repos, "RStudio", exact = TRUE)
  if (identical(rstudio, TRUE)) {
    cran <- repos[["CRAN"]]
    if (startswith(cran, "https://cran.rstudio.") ||
        startswith(cran, "https://cran.posit."))
    {
      repos[["CRAN"]] <- config$ppm.url()
      return(repos)
    }
  }

  # if no repository was set, use PPM
  if (identical(repos, list(CRAN = "@CRAN@")))
    return(config$ppm.url())

  # repos appears to have been configured separately; just use it
  repos

}
