
library( TCGAbiolinks, quietly = TRUE  )
library( biomaRt )
library( vsn, quietly = TRUE )
library( DESeq2, quietly = TRUE )
library( limma, quietly = TRUE )
library( tibble, quietly = TRUE )
library( dplyr, quietly = TRUE )
library( openxlsx )

## Paths
OBJECT_PATH <- file.path( "data", "objects" )

## Dependent data sources

## Sanchez et al. oncogenic RAS pathway definition
RAS_PATHWAY_DEF_FILE <- file.path( "data", "downloads", "1-s2.0-S0092867418303593-mmc3.xlsx" )

## Oncogenic alternation data
ONCOGENIC_PATHWAY_ALTERATIONS_FILE <- file.path( "data", "downloads", "1-s2.0-S0092867418303593-mmc4.xlsx" )

## Cell TCGA immune landscape data
IMMUNE_LANDSCAPE_DATA_FILE <- file.path( "data",
                                        "downloads",
                                        "1-s2.0-S1074761318301213-mmc2.xlsx" )

## set TCGA tumour name for download
tumour <- "LUAD"
project <- paste( "TCGA", tumour, sep = "-" )

## Download TCGA RSEM RNA-seq quantifications from GDC legacy
query_rnaseq <- GDCquery( project = project,
                         data.category = "Gene expression",
                         data.type = "Gene expression quantification",
                         platform = "Illumina HiSeq", 
                         file.type  = "results",
                         experimental.strategy = "RNA-Seq",
                         legacy = TRUE )
GDCdownload( query_rnaseq, method = "api" )

## Create a SummarizedExperiment object and save
se <- GDCprepare( query = query_rnaseq,
                  summarizedExperiment = TRUE )
saveRDS( se, file.path( OBJECT_PATH, paste0( "se_", tumour, ".rds" ) ) )

load( "../../data/GDCdata/GDCdata/TCGA-LUAD/legacy/Gene_expression/se_TCGA-LUAD.RNA-Seq.legacy.biolinks.rda" )

## - Rename assays slots for DESeq2 compatibility
names( assays( se ) ) <- c( "counts", "scaled_estimate" )

## round counts
assay( se ) <- round( assay( se ) )

## - remove duplicate gene entries
se <- se[ !duplicated( rownames( se ) ), ]

## add feature id to id column in rowData
rowData( se )$id <- rownames( assay( se ) )

## vst normalise and save to SE object
vst_res <- varianceStabilizingTransformation( assay( se ) )
rownames( vst_res ) <- sub( "\\.\\d+$", "", rownames( vst_res ) )
assays( se )$vst <- vst_res

## Add TCGA pancancer sample id to enable mapping to pancancer data resources
se$pancan_pathway <- sub( "[AB]$", "", se$sample )

## Add tumour normal label column
se$tumour_normal <- "tumour"
se$tumour_normal[ se$definition %in% "Solid Tissue Normal" ] <- "normal"


## Select tumour samples
se_t <- se[ ,!se$definition %in% "Solid Tissue Normal" ]

## Load oncogenic-RAS pathway definition
rasPathwayTab <- read.xlsx( RAS_PATHWAY_DEF_FILE, sheet = 8, check.names = TRUE )
rasGeneSets <- list( og = subset( rasPathwayTab, OG.TSG == "OG" )$Gene,
                    tsg = subset( rasPathwayTab, OG.TSG == "TSG" )$Gene )
rasGeneSets <- lapply( rasGeneSets, as.character )
ras_pathway_genes <- unlist( rasGeneSets )

## - Load and add oncogenic pathway alteration data
alt_altDat <- read.xlsx( ONCOGENIC_PATHWAY_ALTERATIONS_FILE, sheet = 1, startRow = 3 )

df <- colData( se_t ) %>%
    as.data.frame( ) %>%
    left_join( alt_altDat, by = c( "pancan_pathway" = "SAMPLE_BARCODE" ) )
colData( se_t ) <- DataFrame( df, row.names = df$rowname )

## Identify RAS pathway alterations
alt_genes <- sapply( strsplit( colnames( alt_altDat )[ -1 ], "\\." ), '[[', 2 )
rasAlts_f <- alt_genes %in% unlist( rasGeneSets )
rasAlts <- colnames( alt_altDat )[ -1 ][ rasAlts_f ]
rasAlts <- rasAlts[ colSums( as.matrix( colData( se_t )[, rasAlts ] ), na.rm = TRUE ) > 0 ]

## Identify RAS pathway alterations
onco_ras_labels <- colData( se_t ) %>%
    as.data.frame( ) %>% 
    dplyr::select( sample, one_of( rasAlts ) ) %>%
    tidyr::gather( name, value, -sample ) %>%
    filter( name %in% rasAlts ) %>%
    group_by( sample ) %>%
    dplyr::summarize( onco_ras = ifelse( all( !value ), "oncoras_neg",
                          ifelse( any( name == "MUT.KRAS" & value ), "kras_mut", "oncoras_pos" ) ) ) %>%
    as.data.frame( )

## Add alterations to tumour SE object
df <- colData( se_t ) %>%
    as.data.frame( ) %>%
    left_join( onco_ras_labels, by = "sample" )
colData( se_t ) <- DataFrame( df, row.names = df$rowname )

## Load TCGA PanCancer immune landscape paper metrics
cell_imm_lscape_dat <- read.xlsx( IMMUNE_LANDSCAPE_DATA_FILE )
dup_colnames_f <- colnames( cell_imm_lscape_dat ) %>% duplicated()
colnames( cell_imm_lscape_dat )[ dup_colnames_f ] <- paste0( colnames( cell_imm_lscape_dat )[ dup_colnames_f ], "_2" )

## Add immune landscape data to tumour SE object
df <- colData( se_t ) %>%
  as.data.frame( ) %>%
  left_join( cell_imm_lscape_dat, by = c( "patient" = "TCGA.Participant.Barcode" ) )
colData( se_t ) <- DataFrame( df, row.names = df$rowname )

## save SE objects
save( se, file = file.path( OBJECT_PATH, paste0( "se_", project, ".RNA-Seq.legacy.biolinks.rda") ) )
save( se_t, file = file.path( OBJECT_PATH, paste0( "se_t_", project, ".RNA-Seq.legacy.biolinks.rda") ) )
