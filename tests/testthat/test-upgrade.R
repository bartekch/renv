
test_that("the version of renv in a project can be changed (upgraded)", {

  skip_slow()

  renv_tests_scope()
  init()

  # with a version number
  upgrade(version = "0.5.0")
  expect_equal(renv_activate_version("."), "32f0f78d87150a8656a99223396f844e2fac7a17")

  # or with a sha
  upgrade(version = "5049cef8a")
  expect_equal(renv_activate_version("."), "5049cef8a94591b802f9766a0da092780f59f7e4")

})
