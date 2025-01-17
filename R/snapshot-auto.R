
`_renv_library_info` <- NULL

`_renv_snapshot_running` <- FALSE
`_renv_snapshot_suppressed` <- FALSE

# nocov start
renv_snapshot_auto <- function(project) {

  # set some state so we know we're running
  `_renv_snapshot_running` <<- TRUE
  defer(`_renv_snapshot_running` <<- FALSE)

  # passed pre-flight checks; snapshot the library
  # validation messages can be noisy; turn off for auto snapshot
  status <- catch(renv_snapshot_auto_impl(project))
  if (inherits(status, "error"))
    return(FALSE)

  lockfile <- renv_lockfile_path(project = project)
  writef("* Automatic snapshot has updated '%s'.", renv_path_aliased(lockfile))
  TRUE

}

renv_snapshot_auto_impl <- function(project) {

  # be quiet during auto snapshot
  renv_scope_options(
    renv.config.snapshot.validate = FALSE,
    renv.verbose = FALSE
  )

  # perform snapshot without prompting
  snapshot(project = project, prompt = FALSE)

}

renv_snapshot_auto_enabled <- function(project) {

  # don't auto-snapshot if disabled by user
  enabled <- config$auto.snapshot()
  if (!enabled)
    return(FALSE)

  # only automatically snapshot the current project
  if (renv_project_loaded(project))
    return(FALSE)

  # don't auto-snapshot if the project hasn't been initialized
  if (!renv_project_initialized(project = project))
    return(FALSE)

  # don't auto-snapshot if we don't have a library
  library <- renv_paths_library(project = project)
  if (!file.exists(library))
    return(FALSE)

  # don't auto-snapshot unless the active library is the project library
  if (!renv_file_same(renv_libpaths_active(), library))
    return(FALSE)

  TRUE

}

renv_snapshot_auto_update <- function(project) {

  # check for enabled
  if (!renv_snapshot_auto_enabled(project = project))
    return(FALSE)

  # get path to project library
  libpath <- renv_paths_library(project = project)
  if (!file.exists(libpath))
    return(FALSE)

  # list files + get file info for files in project library
  info <- renv_file_info(libpath)

  # only keep relevant fields
  fields <- c("size", "mtime", "ctime")
  new <- c(info[fields])

  # update our cached info
  old <- `_renv_library_info`
  `_renv_library_info` <<- new

  # if we've suppressed the next automatic snapshot, bail here
  if (`_renv_snapshot_suppressed`) {
    `_renv_snapshot_suppressed` <<- FALSE
    return(FALSE)
  }

  # report if things have changed
  !is.null(old) && !identical(old, new)

}

renv_snapshot_task <- function() {

  # check for active renv project
  project <- renv_project_get()
  if (is.null(project))
    return()

  # see if library state has updated
  updated <- renv_snapshot_auto_update(project = project)
  if (!updated)
    return()

  # library has updated; perform auto snapshot
  renv_snapshot_auto(project = project)

}

renv_snapshot_auto_suppress_next <- function() {

  # if we're currently running an automatic snapshot, then nothing to do
  if (`_renv_snapshot_running`)
    return()

  # otherwise, set the suppressed flag
  `_renv_snapshot_suppressed` <<- TRUE

}

# nocov end
