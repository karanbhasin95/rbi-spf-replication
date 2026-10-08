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
capture mkdir "`root'/results"
capture erase "`root'/.replication_build_complete.tmp"

do "`root'/code/tables/table_01.do"
do "`root'/code/tables/table_02.do"
do "`root'/code/tables/table_03.do"
do "`root'/code/tables/table_04.do"
do "`root'/code/tables/table_05.do"
do "`root'/code/tables/table_07.do"

do "`root'/code/figures/figure_01.do"
do "`root'/code/figures/figure_02.do"
do "`root'/code/figures/figure_03.do"
do "`root'/code/figures/figure_04.do"
do "`root'/code/figures/figure_05.do"
do "`root'/code/figures/figure_06.do"
do "`root'/code/figures/figure_07.do"
do "`root'/code/figures/figure_08.do"
do "`root'/code/figures/appendix_figure_d1.do"
do "`root'/code/figures/appendix_figure_d2.do"

display as result "REPLICATION_BUILD_COMPLETE"
tempname marker
file open `marker' using "`root'/.replication_build_complete.tmp", write text replace
file write `marker' "REPLICATION_BUILD_COMPLETE" _n
file close `marker'
