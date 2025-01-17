% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/status.R
\name{status}
\alias{status}
\title{Report differences between lockfile and project library}
\usage{
status(
  project = NULL,
  ...,
  library = NULL,
  lockfile = NULL,
  sources = TRUE,
  cache = FALSE
)
}
\arguments{
\item{project}{The project directory. If \code{NULL}, then the active project will
be used. If no project is currently active, then the current working
directory is used instead.}

\item{...}{Unused arguments, reserved for future expansion. If any arguments
are matched to \code{...}, renv will signal an error.}

\item{library}{The library paths. By default, the library paths associated
with the requested project are used.}

\item{lockfile}{Path to a lockfile. When \code{NULL} (the default), the \code{renv.lock} located in the root of the current project will be used.}

\item{sources}{Boolean; check that each of the recorded packages have a
known installation source? If a package has an unknown source, renv
may be unable to restore it.}

\item{cache}{Boolean; perform diagnostics on the global package cache?
When \code{TRUE}, renv will validate that the packages installed into the
cache are installed at the expected + proper locations, and validate the
hashes used for those storage locations.}
}
\value{
This function is normally called for its side effects, but
it invisibly returns a list containing the following components:
\itemize{
\item \code{library}: packages in your library.
\item \code{lockfile}: packages in the lockfile.
\item \code{synchronized}: are the library and lockfile in sync?
}
}
\description{
Report differences between the project's lockfile and the current state of
the project's library (if any).
}
\examples{

\dontrun{

# disable automatic snapshots
auto.snapshot <- getOption("renv.config.auto.snapshot")
options(renv.config.auto.snapshot = FALSE)

# initialize a new project (with an empty R library)
renv::init(bare = TRUE)

# install digest 0.6.19
renv::install("digest@0.6.19")

# save library state to lockfile
renv::snapshot()

# remove digest from library
renv::remove("digest")

# check library status
renv::status()

# restore lockfile, thereby reinstalling digest 0.6.19
renv::restore()

# restore automatic snapshots
options(renv.config.auto.snapshot = auto.snapshot)

}
}
