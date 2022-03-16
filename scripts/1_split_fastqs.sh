#!/bin/bash
#
#SBATCH --job-name=1_split_fastqs
#SBATCH --cpus-per-task=2
#SBATCH --nodes=1
#SBATCH --time=4-00:00:00
#SBATCH --partition=cgawad

START_TIME=$(date +%s)
FASTQ_DIR=$1
RESULTS_DIR=$2
R1_SUFFIX=$3
R2_SUFFIX=$4
PYTHON_LIBS=$5
PYTHON_LIBS_SITE_PACKAGES=$6
READS_PER_SPLIT=$7
SAMPLE_ARRAY=( $(echo ${8} | sed 's/:/ /g') )
SAMPLE=${SAMPLE_ARRAY[$(( $SLURM_ARRAY_TASK_ID - 1 ))]}

echo -e "START: $(date)\nRNA Pipeline\nSlurm ID: $SLURM_ARRAY_TASK_ID\nFastq dir: $FASTQ_DIR\nResults dir: $RESULTS_DIR"
cd $RESULTS_DIR

ml python/3.6.1
export PATH=${PYTHON_LIBS}:$PATH
export PYTHONPATH=${PYTHON_LIBS_SITE_PACKAGES}:$PYTHONPATH

echo "START: $(date)"

SPLIT_DIR="${RESULTS_DIR}/split_aligning_$SAMPLE"
echo "Sample: $SAMPLE"

R1_FASTQ="${FASTQ_DIR}/${SAMPLE}${R1_SUFFIX}"
R2_FASTQ="${FASTQ_DIR}/${SAMPLE}${R2_SUFFIX}"
echo "### Counting fastq read counts ### - START: $(date)"
READ_COUNT=$(echo $(zcat $R1_FASTQ | wc -l ) \
    $(zcat $R2_FASTQ | wc -l) | awk '{ print ($1 + $2) / 4 }' )
echo -e "sample\tread_count" > ${SAMPLE}.read_counts.tsv
echo -e "$SAMPLE\t$READ_COUNT" >> ${SAMPLE}.read_counts.tsv
echo "### Counting fastq read counts ### - END: $(date)"


echo "### Splitting Fastqs ### - START: $(date)"
if [ ! -d $SPLIT_DIR ]; then
    mkdir $SPLIT_DIR
    echo "Made directory to split fastqs: $SPLIT_DIR"
fi
LINES_PER_SPLIT=$(($READS_PER_SPLIT * 4))
zcat $R1_FASTQ | split --suffix-length=3 --numeric-suffixes=1 -l $LINES_PER_SPLIT - ${SPLIT_DIR}/${SAMPLE}_R1_split_
zcat $R2_FASTQ | split --suffix-length=3 --numeric-suffixes=1 -l $LINES_PER_SPLIT - ${SPLIT_DIR}/${SAMPLE}_R2_split_
for file in ${SPLIT_DIR}/${SAMPLE}_R1_split_*; do 
    mv $file ${file}.fastq; 
done
for file in ${SPLIT_DIR}/${SAMPLE}_R2_split_*; do 
    mv $file ${file}.fastq; 
done
echo "### Splitting Fastqs ### - END: $(date)"


echo -e "END: $(date)\nRuntime: $(($(date +%s)-$START_TIME)) seconds"
if [ $(ls split_aligning_${SAMPLE}/${SAMPLE}_R1_split_[0-9]*.fastq | wc -l) -eq 0 ]; then
    echo "No split fastqs found. Exiting with code 1"
    exit 1
fi