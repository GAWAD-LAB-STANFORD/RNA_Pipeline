#!/bin/bash
#
#SBATCH --job-name=summarize_metrics
#SBATCH --cpus-per-task=2
#SBATCH --nodes=1
#SBATCH --time=1-00:00:00
#SBATCH --partition=cgawad

START_TIME=$(date +%s)
RESULTS_DIR=$1
SCRIPT_DIR=$2
PROJECT=$3
RUN_DIR=$4
SAMPLE_SHEET=$5

cd $RESULTS_DIR

ml R/4.0.2 biology samtools
export R_LIBS="/home/groups/cgawad/R_LIBS"

echo "### Summarizing metrics ### - START: $(date)"
SAMPLE_READ_COUNTS="${PROJECT}.sample_read_counts.tsv"
READ_COUNT_FILENAMES=( $(ls *.read_counts.tsv) )
head -n 1 ${READ_COUNT_FILENAMES[0]} > $SAMPLE_READ_COUNTS
for i in ${READ_COUNT_FILENAMES[@]}; do tail -n +2 $i; done >> $SAMPLE_READ_COUNTS
if [ ! -z $RUN_DIR ]; then
    DESIRED_CLUSTER_DENSITY=$(sed -n $(grep -n "Lane" $SAMPLE_SHEET | sed "s/:Lane.*//" | \
        awk '{print $1 + 1}')p $SAMPLE_SHEET | cut -d , -f $(grep "Lane" $SAMPLE_SHEET | \
        sed "s/,/\n/g" | nl | grep "Desired_Cluster_Density" | cut -f 1))
    INITAL_CONCENTRATION_COLUMN=$(grep "Initial_Concentration" $SAMPLE_SHEET | tr , "\n" | nl | grep "Initial_Concentration" | cut -f 1)
    LIBRARY_GROUP_COLUMN=$(grep "Library_Group" $SAMPLE_SHEET | tr , "\n" | nl | grep "Library_Group" | cut -f 1)
    if [ ! -z $INITAL_CONCENTRATION_COLUMN ] && [ ! -z $DESIRED_CLUSTER_DENSITY ]; then
        echo "### Calculating library concentration corrections ### - START: $(date)"
        cat $SAMPLE_READ_COUNTS > ${SAMPLE_READ_COUNTS}.temp
        tail -n +$(cat -n $SAMPLE_SHEET | grep "Initial_Concentration" | cut -f 1 | tr -d '[:blank:]') $SAMPLE_SHEET | \
            cut -d , -f $INITAL_CONCENTRATION_COLUMN | awk '{print tolower($0)}' | \
            paste ${SAMPLE_READ_COUNTS}.temp - > $SAMPLE_READ_COUNTS
        if [ ! -z $LIBRARY_GROUP_COLUMN ]; then
            cat $SAMPLE_READ_COUNTS > ${SAMPLE_READ_COUNTS}.temp
            tail -n +$(cat -n $SAMPLE_SHEET | grep "Library_Group" | cut -f 1 | tr -d '[:blank:]') $SAMPLE_SHEET | \
                cut -d , -f $LIBRARY_GROUP_COLUMN | awk '{print tolower($0)}' | \
                paste ${SAMPLE_READ_COUNTS}.temp - > $SAMPLE_READ_COUNTS
        fi
        rm ${SAMPLE_READ_COUNTS}.temp
        Rscript ${SCRIPT_DIR}/correct_library_concentrations.R \
            "${RUN_DIR}/RunCompletionStatus.xml" $DESIRED_CLUSTER_DENSITY $SAMPLE_READ_COUNTS $PROJECT
        echo "### Calculating library concentration corrections ### - END: $(date)"
    fi
fi

ALIGNMENT_METRICS_FILENAMES=( $(ls *.multiple_metrics.alignment_summary_metrics.tsv) )
echo -e sample"\t"$(head -n 7 ${ALIGNMENT_METRICS_FILENAMES[0]} | tail -n 1) | sed 's/ /\t/g' > ${PROJECT}.merged_alignment_metrics.tsv
for i in ${ALIGNMENT_METRICS_FILENAMES[@]}; do 
    SAMPLE=$(echo $i | sed "s/.multiple_metrics.alignment_summary_metrics.tsv//")
    R1=$(head -n 8 $i | tail -n 1)
    R2=$(head -n 9 $i | tail -n 1)
    PAIR=$(head -n 10 $i | tail -n 1)
    echo -e "$SAMPLE\t$R1\n$SAMPLE\t$R2\n$SAMPLE\t$PAIR"
done | sed 's/ /\t/g' >> ${PROJECT}.merged_alignment_metrics.tsv
echo "Merged alignment metrics"

WGS_METRICS_SUFFIX=".wgs_metrics.tsv"
WGS_METRICS_MERGED="${PROJECT}.merged_wgs_metrics.tsv"
WGS_METRICS_FILENAMES=( $(ls *${WGS_METRICS_SUFFIX}) )
echo -e sample"\t"$(head -n 7 ${WGS_METRICS_FILENAMES[0]} | tail -n 1) | sed 's/ /\t/g' > $WGS_METRICS_MERGED
for i in ${WGS_METRICS_FILENAMES[@]}; do echo -e $(echo $i | sed "s/$WGS_METRICS_SUFFIX//")"\t"$(head -n 8 $i | tail -n 1); done | sed 's/ /\t/g' >> $WGS_METRICS_MERGED
echo "Merged WGS metrics"

OXOG_METRICS_FILENAMES=( $(ls *.oxog_metrics.tsv) )
head -n 7 ${OXOG_METRICS_FILENAMES[0]} | tail -n 1 > ${PROJECT}.merged_oxog_metrics.tsv
for i in ${OXOG_METRICS_FILENAMES[@]}; do tail -n +8 $i | awk NF >> ${PROJECT}.merged_oxog_metrics.tsv; done
echo "Merged oxog metrics"

DUPLICATION_METRICS_FILENAMES=( $(ls *.duplication_metrics.tsv) )
head -n 7 ${DUPLICATION_METRICS_FILENAMES[0]} | tail -n 1 > ${PROJECT}.merged_duplication_metrics.tsv
for i in ${DUPLICATION_METRICS_FILENAMES[@]}; do head -n 8 $i | tail -n 1 >> ${PROJECT}.merged_duplication_metrics.tsv; done
echo "Merged duplication metrics"

COVERAGE_FILENAMES=( $(ls *.wgs_coverage.tsv) )
echo -e "sample\tchrM_proportion" > ${PROJECT}.merged_chrM_proportions.tsv
for i in ${COVERAGE_FILENAMES[@]}; do
    MAIN_CHR_COUNTS=$(tail -n +2 $i | cut -f 4 | paste -sd+ | bc)
    CHRM_COUNTS=$(grep -P "chrM\t" $i | cut -f 4)
    echo -e $(echo $i | sed "s/.wgs_coverage.tsv//")"\t"$(awk 'BEGIN {print('$CHRM_COUNTS'/'$MAIN_CHR_COUNTS')}')
done >> ${PROJECT}.merged_chrM_proportions.tsv
echo "Merged chrM proportions"

COVERAGE_FILENAMES=( $(ls *.wgs_coverage.tsv) )
for i in ${COVERAGE_FILENAMES[@]}; do
    SAMPLE=$(echo $i | sed "s/.wgs_coverage.tsv//")
    cut -f 4,7 $i | sed "s/covered_features/${SAMPLE}_depth/" | \
        sed "s/breadth_coverage_fraction/${SAMPLE}_breadth/" > ${SAMPLE}.temp_coverage.tsv
done
TEMP_COVERAGE_FILENAMES=( $(ls *.temp_coverage.tsv) )
cut -f 1,2,3,6 ${COVERAGE_FILENAMES[0]} | \
    paste - ${TEMP_COVERAGE_FILENAMES[@]} > ${PROJECT}.merged_wgs_coverage.tsv
rm ${TEMP_COVERAGE_FILENAMES[@]}
echo "Merged coverage"
Rscript ${SCRIPT_DIR}/graph_coverage.R ${PROJECT}.merged_wgs_coverage.tsv $PROJECT "wgs"

DOWN_SAMPLE_COV_FILENAMES=( $(ls *.wgs_5M_read_coverage.tsv) )
if [ ${#DOWN_SAMPLE_COV_FILENAMES[@]} -ne 0 ]; then
    for i in ${DOWN_SAMPLE_COV_FILENAMES[@]}; do
        SAMPLE=$(echo $i | sed "s/.wgs_5M_read_coverage.tsv//")
        cut -f 4,7 $i | sed "s/covered_features/${SAMPLE}_depth/" | \
            sed "s/breadth_coverage_fraction/${SAMPLE}_breadth/" > ${SAMPLE}.temp_coverage.tsv
    done
    TEMP_COVERAGE_FILENAMES=( $(ls *.temp_coverage.tsv) )
    cut -f 1,2,3,6 ${DOWN_SAMPLE_COV_FILENAMES[0]} | \
        paste - ${TEMP_COVERAGE_FILENAMES[@]} > ${PROJECT}.merged_wgs_coverage_5M_reads.tsv
    rm ${TEMP_COVERAGE_FILENAMES[@]}
    echo "Merged 5M coverage"
    Rscript ${SCRIPT_DIR}/graph_coverage.R ${PROJECT}.merged_wgs_coverage_5M_reads.tsv $PROJECT "5M_reads_wgs"
    
    DOWN_SAMPLE_PRESEQ_FILENAMES=( $(ls *.gc_extrap.future_coverage_5M.tsv) )
    head -n 1 ${DOWN_SAMPLE_PRESEQ_FILENAMES[0]} | sed "s/^/SAMPLE\t/" > ${PROJECT}.merged_preseq_future_coverage_5M.tsv
    for i in ${DOWN_SAMPLE_PRESEQ_FILENAMES[@]}; do
        SAMPLE=$(echo $i | sed "s/.gc_extrap.future_coverage_5M.tsv//")
        tail -n +2 $i | sed "s/^/${SAMPLE}\t/" >> ${PROJECT}.merged_preseq_future_coverage_5M.tsv
    done
    echo "Merged preseq future coverage"
    Rscript ${SCRIPT_DIR}/graph_preseq.R ${PROJECT}.merged_preseq_future_coverage_5M.tsv $PROJECT "5M_reads"
fi

PRESEQ_FILENAMES=( $(ls *.gc_extrap.future_coverage.tsv) )
head -n 1 ${PRESEQ_FILENAMES[0]} | sed "s/^/SAMPLE\t/" > ${PROJECT}.merged_preseq_future_coverage.tsv
for i in ${PRESEQ_FILENAMES[@]}; do
    SAMPLE=$(echo $i | sed "s/.gc_extrap.future_coverage.tsv//")
    tail -n +2 $i | sed "s/^/${SAMPLE}\t/" >> ${PROJECT}.merged_preseq_future_coverage.tsv
done
echo "Merged preseq future coverage"
Rscript ${SCRIPT_DIR}/graph_preseq.R ${PROJECT}.merged_preseq_future_coverage.tsv $PROJECT

VARIANT_CLASS_COUNTS_FILENAMES=( $(ls *.variant_class_counts.tsv) )
head -n 1 ${VARIANT_CLASS_COUNTS_FILENAMES[0]} | sed "s/^/sample\t/" > ${PROJECT}.merged_variant_class_counts.tsv
for i in ${VARIANT_CLASS_COUNTS_FILENAMES[@]}; do
	SAMPLE=$(echo $i | sed "s/.variant_class_counts.tsv//")
	tail -n +2 $i | sed "s/^/${SAMPLE}\t/" >> ${PROJECT}.merged_variant_class_counts.tsv
done 
Rscript ${SCRIPT_DIR}/variant_class_analysis.R ${PROJECT}.merged_variant_class_counts.tsv $PROJECT
echo "### Summarizing metrics ### - END: $(date)"

echo "### Deleting intermediate files ### - START: $(date)"
rm ${READ_COUNT_FILENAMES[@]} ${ALIGNMENT_METRICS_FILENAMES[@]} ${WGS_METRICS_FILENAMES[@]} ${OXOG_METRICS_FILENAMES[@]}
rm ${CHRM_PROP_FILENAMES[@]} ${COVERAGE_FILENAMES[@]} ${DOWN_SAMPLE_COV_FILENAMES[@]} ${DUPLICATION_METRICS_FILENAMES[@]}
rm ${PRESEQ_FILENAMES[@]} ${DOWN_SAMPLE_PRESEQ_FILENAMES[@]} ${VARIANT_CLASS_COUNTS_FILENAMES[@]}
mkdir -p ${PROJECT}_Multiple_Metric_Files
mv *multiple_metrics* ${PROJECT}_Multiple_Metric_Files/
if [ -f ${PROJECT}.temporary_3_column_bed_interval_file ]; then
    rm ${PROJECT}.temporary_3_column_bed_interval_file
fi
echo "### Deleting intermediate files ### - END: $(date)"
echo -e "END: $(date)\nRuntime: $(($(date +%s)-$START_TIME)) seconds"