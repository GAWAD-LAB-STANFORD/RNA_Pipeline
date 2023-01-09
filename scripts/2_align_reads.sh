#!/bin/bash
#
#SBATCH --job-name=2_align_reads
#SBATCH --cpus-per-task=1
#SBATCH --nodes=1
#SBATCH --time=4-00:00:00
#SBATCH --partition=cgawad

START_TIME=$(date +%s)
RESULTS_DIR=$1
REF_FASTA=$2
TOOLS_DIR=$3
FASTQ_ARRAY=( $(echo $4 | sed 's/:/ /g') )
FASTQ=${FASTQ_ARRAY[$(( $SLURM_ARRAY_TASK_ID - 1 ))]}
RNA=$6

SPLIT_DIR=$(dirname $FASTQ)
R1_FASTQ=$(basename $FASTQ)
R2_FASTQ=$(echo $R1_FASTQ | sed "s/_R1_split_/_R2_split_/")
SPLIT_NUM=$(echo $R1_FASTQ | sed "s/.*_R1_split_//" | sed "s/.fastq//")
SAMPLE=$(echo $R1_FASTQ | sed "s/_R1_split_.*//")
ALIGNED_BAM=$(echo $R1_FASTQ | sed "s/_R1_split_.*/_split_${SPLIT_NUM}.bam/")

echo -e "START: $(date)\nRNA Pipeline\nSlurm ID: $SLURM_ARRAY_TASK_ID\nSplit dir: $SPLIT_DIR\nR1 fastq: $R1_FASTQ\nSplit num: $SPLIT_NUM\nSample: $SAMPLE\n"
cd $RESULTS_DIR

ml python/3.6.1 java/11.0.11 
ml biology bwa samtools gatk star/2.5.4b
echo "### Aligning fastqs - RNA data specified ### - START: $(date)"
STAR --genomeDir \
    /oak/stanford/groups/cgawad/Reference_Files/GATK_Resource_Bundle_hg38/hg38_STAR_index/ \
    --readFilesIn ${SPLIT_DIR}/${R1_FASTQ} ${SPLIT_DIR}/${R2_FASTQ} \
    --runThreadN 2 \
    --outFileNamePrefix ${SPLIT_DIR}/${ALIGNED_BAM} \
    --outSAMtype BAM SortedByCoordinate \
    --outSAMunmapped Within \
    --outSAMattributes Standard
echo "### Aligning fastqs - RNA data specified ### - START: $(date)"
mv ${SPLIT_DIR}/${ALIGNED_BAM}Aligned.sortedByCoord.out.bam ${SPLIT_DIR}/${ALIGNED_BAM}
echo -e "END: $(date)\nRuntime: $(($(date +%s)-$START_TIME)) seconds"