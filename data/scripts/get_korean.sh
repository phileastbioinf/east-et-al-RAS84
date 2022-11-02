#!/bin/bash

wget --output-document=data/downloads/GSE40419_LC-87_RPKM_expression.txt "https://www.ncbi.nlm.nih.gov/geo/download/?acc=GSE40419&format=file&file=GSE40419%5FLC%2D87%5FRPKM%5Fexpression%2Etxt%2Egz"
wget -P data/downloads "https://genome.cshlp.org/content/suppl/2012/09/14/gr.145144.112.DC1/SuppTable3.xls"
