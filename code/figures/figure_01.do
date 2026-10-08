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

use "`data'", clear
keep if record_type == "macro_history"
keep macro_year macro_real_gdp_growth macro_cpi_inflation
rename macro_year year
rename macro_real_gdp_growth real_gdp_growth
rename macro_cpi_inflation cpi_inflation
keep if inrange(year, 1951, 2022)
isid year
assert _N == 72
sort year

twoway ///
    (line real_gdp_growth year, lcolor(black) lwidth(medthick)) ///
    (connected cpi_inflation year, lcolor(gs8) lpattern(longdash) ///
        lwidth(medthick) mcolor(gs8) msymbol(square) msize(small)), ///
    yscale(range(-15 30)) ylabel(-15(15)30, angle(horizontal) grid) ///
    xscale(range(1950.5 2022.5)) xlabel(1951(2)2021, angle(90) labsize(small)) ///
    xtitle("") ytitle("") ///
    legend(order(1 "RGDP" 2 "CPI Inflation") rows(1) ring(0) position(12) ///
        region(lstyle(none) fcolor(none))) ///
    graphregion(color(white)) plotregion(color(white)) ///
    xsize(12.225) ysize(5)
graph export "`out'/figure01.png", replace width(2978)
