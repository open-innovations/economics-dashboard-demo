library(shiny)
library(patchwork)
library(bslib)
library(DT)
library(plotly)

# UI ----------------------------------------------------------------------

logos <- div(
  p("A microsite built by Open Innovations",
    style = "font-size: 0.8em; float:right; text-align:center"),
  a(
    img(
      src = "oi-square.png",
      height = 50,
      width = 50,
      style = "float:right; margin-left: 10px"
    ),
    href = "https://open-innovations.org", target = "_blank"
  )
)

ui <- bslib::page_fluid(
  bslib::page_navbar(
    title = "Economics Dashboard Demo",
    id = "navbar",
    collapsible = TRUE,
    bg = "#722EA5",
    window_title = "Economics Dashboard Demo",
    header = list(
      logos,
      p(
        paste(
          "This is a demo site in active development and subject to change. Last updated on",
          format(file.info("all_data.csv")$mtime, "%d %B %Y at %H:%M")
        ),
        style = "background-color: #000000; text-align: center;
        color: #FFFFFF;
        padding: 10px; margin-top: 10px"
      ),
      checkboxInput("filter_2018",
                    label = "Show only data from 2018 onwards",
                    value = TRUE)
    ),
    footer = logos,

    tabPanel(
      title = "Dashboard",
      value = "dashboard",
      titlePanel("Latest economic indicators"),
      uiOutput("dashboardUI")
    ),

    tabPanel(
      title = "Time series",
      value = "time-series",
      titlePanel("Historic economic indicators"),
      uiOutput("headlineUI")
    ),

    tabPanel(
      title = "Data",
      value = "data",
      titlePanel("Explore and download the data"),
      uiOutput("data_table")
    ),

    # tabPanel(
    #   title = "About",
    #   value = "about",
    #   titlePanel("About"),
    #   h3("About this dashboard"),
    #   p("This microsite was built by Open Innovations as part of a partnership with Leeds City Council where Open Innovations provides economic and data science expertise to the Council to help them exploit developments in economic data to better support the lives of people living and working in the city."),
    #   p("This microsite, and the code that underpins it, is open source and freely available in a GitHub repository at https://github.com/open-innovations/lcc-economics/inclusive-growth/."),
    #   h3("Data sources:"),
    #   p("Data on employment, self employment, unemployment, economic activity, economic inactivity, and qualifications is sourced from the ONS Annual Population Survey/Labour Force Survey and accessed via NOMIS"),
    #   p("Claimant count data is sourced from an experimental series which counts the number of people claiming Jobseeker's Allowance plus those who claim Universal Credit and are required to seek work and be available for work, and accessed via NOMIS"),
    #   p("Population data is sourced from the ONS mid-year population estimates and accessed via NOMIS"),
    #   p("GVA data is sourced from the ONS Regional Gross Value Added (Balanced) statistics"),
    #   p("Productivity data (GVA per filled job) is sourced from the ONS Sub-regional Productivity Statistics"),
    #   p("Children in Low Income Families data is sourced from DWP Stat-Xplore"),
    #   p("All data is updated automatically when new data is released")
    # )
  )
)

# server ------------------------------------------------------------------

server <- function(input, output, session) {

  # Bookmarking (persistent URLs) -------------------------------------------

  # Automatically bookmark every time an input changes
  observe({
    reactiveValuesToList(input)
    session$doBookmark()
  })

  # Update the query string
  onBookmarked(updateQueryString)

  # Global variables
  plot.theme <- ggplot2::theme(
    panel.background   = ggplot2::element_blank(),
    panel.grid         = ggplot2::element_blank(),
    panel.grid.major.y = ggplot2::element_line(linetype = "dotted"),
    legend.position    = "top",
    axis.line.y.right  = NULL,
    axis.line          = ggplot2::element_line(),
    text               = ggplot2::element_text(size = 12)
  )

  data1 <- readr::read_csv("all_data.csv")

  vNames <- unique(data1$variable_name[data1$is_summary])

  data <- reactive({
    if (input$filter_2018) {
      dplyr::filter(data1, date >= "2018-01-01")
    } else {
      data1
    }
  })

  # Generate dynamic UI components ----------------------------------------

  mini_plots <- reactive({
    lapply(seq_along(vNames), function(x) {
      data() |>
        dplyr::filter(geography_name == 'Leeds',
                      variable_name == vNames[x],
                      is_summary,
                      !is.na(value))
    })
  })

  build_mini_plots <- function(x) {
    sparkline <- plot_ly(mini_plots()[[x]]) |>
      add_lines(
        x = ~date, y = ~value,
        color = I("#000000"), span = I(1)
      ) |>
      layout(
        xaxis = list(visible = F, showgrid = F, title = ""),
        yaxis = list(visible = F, showgrid = F, title = ""),
        hovermode = "x",
        margin = list(t = 0, r = 0, l = 0, b = 0),
        font = list(color = "white"),
        paper_bgcolor = "transparent",
        plot_bgcolor = "transparent"
      ) |>
      config(displayModeBar = F) |>
      htmlwidgets::onRender(
        "function(el) {
          var ro = new ResizeObserver(function() {
            var visible = el.offsetHeight > 200;
            Plotly.relayout(el, {'xaxis.visible': visible});
          });
        ro.observe(el);
        }"
      )
    return(sparkline)
  }

  output$dashboardUI <- renderUI({
    latest_indictors <- lapply(seq_along(vNames), function(x) {
      tempdata <- data() |>
        dplyr::filter(geography_name == 'Leeds',
                      variable_name == vNames[x],
                      is_summary,
                      !is.na(value))

      temp_value <- tempdata$value[tempdata$date == max(tempdata$date)]

      value_box(
        style = 'background-color: #722EA5!important;',
        title = vNames[x],
        value = if (vNames[x] == "GVA") {
          paste0("£", temp_value/1000, "bn")
        } else if (vNames[x] == "Population") {
          paste0(format(temp_value, big.mark = ","))
        } else if (vNames[x] == "GVA per filled job") {
          paste0("£", format(round(temp_value), big.mark = ","))
        } else {
          paste0(temp_value, "%")
        },
        showcase = build_mini_plots(x),
        full_screen = TRUE,
        em(unique(tempdata$variable_name_full), style = "font-size:0.8em"),
        p(
          paste(
            "Latest data is for",
            unique(tempdata$date_name[tempdata$date == max(tempdata$date)])
          )
        ),
        downloadLink(paste0("download_json_", x), label = "JSON")
      )
    })

    layout_column_wrap(
      width = 1/4,
      !!!latest_indictors
    )
  })

  output$headlineUI <- renderUI({
    plots <- lapply(seq_along(vNames), function(x) {
      renderPlotly({
        d1 <- data() |>
          dplyr::filter(geography_name == 'Leeds',
                        variable_name == vNames[x],
                        is_summary,
                        !is.na(value))
        p <- d1 |>
          ggplot2::ggplot(ggplot2::aes(x = date, y = value)) +
          ggplot2::geom_line(colour = "#ED7218") +
          plot.theme +
          ggplot2::labs(title = vNames[x],
                        subtitle = NULL,
                        caption = "caption",
                        x = "",
                        y = "%")
        ggplotly(p) |>
          config(displayModeBar = F) |>
          layout(title = list(text = paste0(vNames[x],
                                            '<br>',
                                            '<sup>',
                                            unique(d1$variable_name_full),
                                            '</sup>')))
      })
    })

    layout_column_wrap(
      width = 1/4,
      !!!plots
    )
  })

  details <- lapply(seq_along(vNames), function(i) {
    this_category <- unique(data1$category[data1$variable_name == vNames[i]])

    # build a list of n plots to be rendered on the tabPanel
    details_charts <- list(
      renderPlotly({
        cities <- data() |>
          dplyr::filter(variable_name == vNames[i]) |>
          dplyr::filter(geography_core_city == TRUE) |>
          dplyr::filter(!is.na(value)) |>
          dplyr::group_by(geography_name) |>
          ggplot2::ggplot(ggplot2::aes(x = date, y = value,
                                       colour = geography_name != "Leeds",
                                       group = geography_name)) +
          ggplot2::geom_line() +
          plot.theme +
          ggplot2::scale_color_manual(values = c("red", "lightgrey")) +
          ggplot2::labs(title = "Core Cities",
                        subtitle = vNames[i],
                        x = "",
                        y = "%",
                        colour = "") +
          ggplot2::theme(legend.position = "top")

        ggplotly(cities,
                 tooltip = c("geography_name", "value")) |>
          layout(showlegend = FALSE)
      }),

      renderPlotly({
        others <- data() |>
          dplyr::filter(variable_name == vNames[i]) |>
          dplyr::filter(geography_core_city == FALSE |
                          geography_name == "Leeds") |>
          dplyr::filter(!is.na(value)) |>
          ggplot2::ggplot(ggplot2::aes(x = date, y = value,
                                       colour = geography_name)) +
          ggplot2::geom_line() +
          plot.theme +
          ggplot2::labs(title = "Other geographies",
                        subtitle = vNames[i],
                        x = "",
                        y = "%",
                        colour = "") +
          ggplot2::theme(legend.position = "top")

        others <- ggplotly(others)
      }),

      renderPlotly({
        breakdown <- data() |>
          dplyr::filter(category == this_category,
                        !is_summary,
                        geography_name == "Leeds",
                        !is.na(value),
                        !grepl("G-U", variable_name)) |> # emp by industry
          dplyr::mutate(variable_name = variable_name |>
                          stringr::str_remove("% all in employment who work in - ") |>
                          stringr::str_remove("\\(SIC 2007\\)") |>
                          stringr::str_remove("% of economically inactive ") |>
                          stringr::str_remove("% who are economically inactive - "))

        if (this_category == "Economic inactivity") {
          breakdown <- breakdown |>
            dplyr::mutate(sub_category = ifelse(grepl("aged", variable_name),
                                                "Inactivity by age",
                                                "Inactivity by reason"))
        }

        if (nrow(breakdown) > 0) {
          breakdown <- breakdown |>
            ggplot2::ggplot(ggplot2::aes(x = date, y = value,
                                         colour = variable_name)) +
            ggplot2::geom_line() +
            {if ("sub_category" %in% names(breakdown)) ggplot2::facet_wrap("sub_category") } +
            plot.theme +
            ggplot2::labs(title = "Detail",
                          x = "",
                          y = "%",
                          colour = "")

          breakdown <- ggplotly(breakdown)
        }
      }),

      if (unique(data1$category[data1$variable_name == vNames[i]]) == "Employment") {
        p("According to analysis from Data City in 2023, there are over 20,000 net zero jobs across 470 companies in Leeds.")
      }
    )

    tabPanel(
      titlePanel(paste("Detail & comparisons:", vNames[i])),
      title = vNames[i],
      value = stringr::str_replace_all(vNames[i], " ", "-"),
      p(unique(data1$variable_name_full[data1$variable_name == vNames[i]])),
      layout_column_wrap(
        width = 1/2,
        !!!details_charts
      )
    )
  })

  # Build details navbarMenu
  # This is done differently to the rest as the contents are dynamic
  # depending on what it is in the data
  details_menu <- do.call(navbarMenu, c("Detail & comparisons", details))

  # Insert details navbarMenu into main navbar
  insertTab("navbar",
            details_menu,
            target = "data",
            position = "before"
  )

  # Data table

  data_table_output <- reactive({
    data() |>
      dplyr::filter(geography_name %in% input$place,
                    category %in% input$category) |>
      dplyr::mutate(variable_name = dplyr::coalesce(variable_name_full,
                                                    variable_name)) |>
      dplyr::select(date = date_name,
                    geography_code,
                    geography_name,
                    category,
                    variable_name,
                    value)
  })

  output$data_table <- renderUI({
    list(
      selectizeInput("place", "Which places to include?",
                     choices = unique(data1$geography_name),
                     selected = "Leeds",
                     multiple = TRUE,
                     options = list(plugins = list("remove_button"))
      ),
      selectizeInput("category", "Which categories to include?",
                     choices = unique(data1$category),
                     selected = "Employment",
                     multiple = TRUE,
                     options = list(plugins = list("remove_button"))
      ),
      downloadButton("download_data",
                     label = "Download as CSV",
                     style = "margin-bottom: 20px"
      ),
      downloadButton("download_json_all",
                     label = "Download as JSON",
                     style = "margin-bottom: 20px"
      ),
      DT::renderDT(data_table_output())
    )
  })

  output$download_data <- downloadHandler(
    filename = function() {
      paste0("leeds-inclusive-growth-data_", Sys.Date(), ".csv")
    },
    content = function(file) {
      readr::write_csv(data_table_output(), file)
    }
  )

  output$download_json_all <- downloadHandler(
    filename = function() {
      paste0("economic-dashboard-demo-", Sys.Date(), ".json")
    },
    content = function(file) {
      jsonlite::write_json(data_table_output(), file)
    }
  )

  lapply(seq_along(vNames), function(x) {
    output[[paste0("download_json_", x)]] <- downloadHandler(
      filename = function() {
        paste0(vNames[x], ".json")
      },
      content = function(file) {
        jsonlite::write_json(mini_plots()[[x]], file)
      }
    )
  })
}

shinyApp(ui = ui, server = server, enableBookmarking = "url")
