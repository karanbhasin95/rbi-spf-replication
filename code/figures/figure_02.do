version 19.0
clear all
set more off
* Locate the package root when run from the root, data/, code/,
* code/tables/, or code/figures/. No machine-specific path is required.
local root ""
foreach candidate in "`c(pwd)'" "`c(pwd)'/.." "`c(pwd)'/../.." {
    if "`root'" == "" {
        capture confirm file "`candidate'/data/baseline_data.dta"
        if !_rc {
            capture confirm file "`candidate'/code/master.do"
            if !_rc local root "`candidate'"
        }
    }
}
if "`root'" == "" {
    display as error "Could not locate the replication package's data/baseline_data.dta."
    display as error "Change directory to the package folder containing code/ and data/, then rerun the whole do-file."
    exit 601
}
local data "`root'/data/baseline_data.dta"
local out "`root'/results/figures"
capture mkdir "`root'/results"
capture mkdir "`out'"
set scheme s2color
graph set window fontface "Times New Roman"

* Convert each reported SPF histogram into its probability-weighted mean.
use "`data'", clear
keep if record_type == "spf_histogram"
keep survey_date survey_year survey_month growth_bin_midpoint ///
    growth_nowcast_probability growth_yearahead_probability

gen double nowcast_component = ///
    growth_bin_midpoint * growth_nowcast_probability
gen double yearahead_component = ///
    growth_bin_midpoint * growth_yearahead_probability
collapse (sum) nowcast_component yearahead_component ///
    growth_nowcast_probability growth_yearahead_probability, ///
    by(survey_date survey_year survey_month)

gen double nowcast_mean = nowcast_component
replace nowcast_mean = . if growth_nowcast_probability == 0
gen double yearahead_mean = yearahead_component
replace yearahead_mean = . if growth_yearahead_probability == 0
assert !missing(nowcast_mean)


sort survey_date
count if missing(yearahead_mean)
assert r(N) == 1
replace yearahead_mean = (yearahead_mean[_n-1] + yearahead_mean[_n+1]) / 2 ///
    if missing(yearahead_mean) & !missing(yearahead_mean[_n-1], yearahead_mean[_n+1])
assert !missing(yearahead_mean)

* Four releases per fiscal target year: early, mid-year, late, and final.
gen byte selected_round = inlist(survey_month, 3, 5, 6, 9, 11, 12)
replace selected_round = 1 if inlist(survey_date, ///
    td(30apr2011), td(30jul2011), td(28jan2023))
keep if selected_round & inrange(survey_date, td(30jun2008), td(28jan2023))

gen int base_year = survey_year - (survey_month <= 3)
bysort base_year (survey_date): gen byte release_order = _n
by base_year: assert _N == 4
assert inrange(base_year, 2008, 2022)

tempfile nowcast_path forecast_path
preserve
    gen int year = base_year
    gen byte horizon = 5 - release_order
    gen double mean_growth_forecast = nowcast_mean

    replace mean_growth_forecast = yearahead_mean if base_year == 2022
    keep year horizon mean_growth_forecast
    save "`nowcast_path'", replace
restore

gen int year = base_year + 1
gen byte horizon = 9 - release_order
gen double mean_growth_forecast = yearahead_mean
keep year horizon mean_growth_forecast
append using "`nowcast_path'"
keep if inrange(year, 2009, 2022)
assert _N == 112
assert inrange(horizon, 1, 8)
assert !missing(mean_growth_forecast)
isid year horizon
save "`forecast_path'", replace

use "`data'", clear
keep if record_type == "annual_gdp"
keep annual_year annual_real_gdp
sort annual_year
tsset annual_year
gen double actual_growth = 100 * (annual_real_gdp / L.annual_real_gdp - 1)
keep if inrange(annual_year, 2009, 2022)
rename annual_year year
gen byte horizon = 0
rename actual_growth mean_growth_forecast
keep year horizon mean_growth_forecast
append using "`forecast_path'"

gen byte path_order = cond(horizon == 0, 9, 9 - horizon)
gen str6 horizon_label = cond(horizon == 0, "Actual", ///
    "H" + string(horizon, "%1.0f"))
sort year path_order
assert _N == 126
assert !missing(year, horizon, path_order, mean_growth_forecast)
isid year path_order

rename path_order h
label define horizon 1 "H8" 2 "H7" 3 "H6" 4 "H5" 5 "H4" 6 "H3" 7 "H2" 8 "H1" 9 "Actual"
label values h horizon
foreach spec in "2009 2010 2011 2012|figure02a.png" ///
                "2013 2014 2015 2016|figure02b.png" ///
                "2017 2018 2019|figure02c.png" ///
                "2020 2021 2022|figure02d.png" {
    gettoken years outfile : spec, parse("|")
    local outfile = subinstr("`outfile'","|","",.)
    local plots ""
    local actuals ""
    local order ""
    local i = 0
    foreach yy of local years {
        local ++i
        if `i' == 1 {
            local style "lcolor(black) lpattern(solid) lwidth(thick) msymbol(none)"
        }
        else if `i' == 2 {
            local style "lcolor(gs8) lpattern(longdash) lwidth(thick) msymbol(none)"
        }
        else if `i' == 3 {
            local style `"lcolor("0 174 239") lpattern(solid) lwidth(thick) msymbol(circle) mcolor("0 174 239") msize(medlarge)"'
        }
        else {
            local style "lcolor(gs13) lpattern(solid) lwidth(thick) msymbol(triangle) mcolor(gs13) msize(medlarge)"
        }
        local plots `"`plots' (connected mean_growth_forecast h if year==`yy', sort `style')"'
        local actuals `"`actuals' (scatter mean_growth_forecast h if year==`yy' & h==9, msymbol(square) mcolor(red) msize(medlarge))"'
        local order `"`order' `i' "`yy'""'
    }
    local yopts "yscale(range(3 15)) ylabel(3(3)15, angle(horizontal) grid)"
    local legendopts "legend(order(`order') rows(1) ring(0) position(12) region(lstyle(none) fcolor(none)))"
    if "`outfile'" == "figure02d.png" {
        local yopts "yscale(range(-12 12)) ylabel(-12(3)12, angle(horizontal) grid)"
        local legendopts "legend(order(`order') cols(2) ring(0) position(7) region(lstyle(none) fcolor(none)))"
    }
    twoway `plots' `actuals', ///
        `yopts' xlabel(1/9, valuelabel angle(horizontal)) ///
        xtitle("") ytitle("") `legendopts' ///
        graphregion(color(white)) plotregion(color(white)) ///
        xsize(8.08) ysize(5)
    graph export "`out'/`outfile'", replace width(1600)
}
