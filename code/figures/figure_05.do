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
keep if record_type == "rbi_disagreement"
keep rbi_round survey_date beta_fit_variance rbi_disagreement
assert _N == 21
assert inrange(rbi_round, 61, 81)
assert beta_fit_variance > 0
isid survey_date

gen double uncertainty = sqrt(beta_fit_variance)
rename rbi_disagreement disagreement
gen md = mofd(survey_date)
format md %tmMon-YY
sort md
assert md[1] == tm(2019m11)
assert md[_N] == tm(2023m3)

twoway (line uncertainty md, lcolor(navy) lwidth(thick)) ///
       (line disagreement md, lcolor(gs8) lwidth(thick)), ///
       ylabel(0(1)10, angle(horizontal) grid glcolor(gs14) glpattern(dot)) ///
       xtitle("") ytitle("") ///
       xlabel(`=tm(2019m11)'(4)`=tm(2023m3)', format(%tmMon-YY) angle(horizontal)) ///
       legend(order(1 "Uncertainty" 2 "Disagreement") rows(1) ///
           position(6) ring(1) region(lstyle(none) fcolor(none))) ///
       graphregion(color(white)) plotregion(color(white)) ///
       xsize(11) ysize(5)
graph export "`out'/figure05.png", replace width(2200)
