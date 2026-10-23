# Why: the deviations vignette must list every help page that has a
# "Deviations from Python" section, and every such page must link to it.
# A new marked section without a vignette entry fails here.

deviation_topics <- function() {
  man <- test_path("..", "..", "man")
  skip_if_not(dir.exists(man), "man pages not available")
  files <- list.files(man, pattern = "\\.Rd$", full.names = TRUE)
  texts <- vapply(
    files,
    function(file) paste(readLines(file), collapse = "\n"),
    character(1)
  )
  names(texts) <- basename(files)
  texts[grepl("Deviations from Python", texts, fixed = TRUE)]
}

test_that("every help page with a Deviations section is in the vignette", {
  vignette_path <- test_path("..", "..", "vignettes", "deviations.Rmd")
  skip_if_not(file.exists(vignette_path), "vignette source not available")
  text <- paste(readLines(vignette_path), collapse = "\n")
  topics <- deviation_topics()
  expect_gt(length(topics), 0L)
  for (file in names(topics)) {
    name <- sub("\\.Rd$", "", file)
    expect_true(
      grepl(paste0("?", name), text, fixed = TRUE),
      info = paste("help page", name, "is missing from the vignette")
    )
  }
})

test_that("every help page named in the vignette has a Deviations section", {
  vignette_path <- test_path("..", "..", "vignettes", "deviations.Rmd")
  skip_if_not(file.exists(vignette_path), "vignette source not available")
  text <- paste(readLines(vignette_path), collapse = "\n")
  named <- regmatches(text, gregexpr("`\\?[A-Za-z0-9_.-]+`", text))[[1]]
  named <- gsub("[`?]", "", named)
  expect_gt(length(named), 0L)
  expect_true(all(paste0(named, ".Rd") %in% names(deviation_topics())))
})

test_that("help pages with a Deviations section link to the vignette", {
  topics <- deviation_topics()
  for (file in names(topics)) {
    expect_true(
      grepl("vignette(\"deviations\")", topics[[file]], fixed = TRUE),
      info = paste("help page", file, "does not link to the vignette")
    )
  }
})
