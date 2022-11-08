#!/bin/bash
#
#SBATCH --job-name=3_process_sample
#SBATCH --cpus-per-task=4
#SBATCH --nodes=1
#SBATCH --time=4-00:00:00
#SBATCH --partition=cgawad

START_TIME=$(date +%s)
RESULTS_DIR=$1
GENOME_VERSION=$2
SCRIPT_DIR=$3
TOOLS_DIR=$4
REFERENCE_DIR=$5
SAMPLE_ARRAY=( $(echo $6 | sed 's/:/ /g') )
SAMPLE=${SAMPLE_ARRAY[$(( $SLURM_ARRAY_TASK_ID - 1 ))]}
DUP_MARK_AGAIN=$7
DUPLICATE_PIXEL_DISTANCE=$8
REMOVE_DUPS=$9
BAM_SUFFIX=${10}
INTERVAL_LIST=${11}
VARIANT_CLASS=${12}

echo -e "START: $(date)\nRNA Pipeline\nSlurm ID: $SLURM_ARRAY_TASK_ID\nSample: $SAMPLE\nResults dir: $RESULTS_DIR\nTargets bed: $TARGETS_BED\nInterval list: $INTERVAL_LIST"
cd $RESULTS_DIR

ml R/4.2.0 java gsl biology samtools bedtools gatk bcftools
export R_LIBS="/home/groups/cgawad/R_LIBS"

# File and directory paths (reference files available in /oak/stanford/groups/cgawad/Reference_Files/)
BEDGRAPH_TO_WIG_TOOL="${TOOLS_DIR}/bedgraph_to_wig.pl"
QUALIMAP_TOOL="${TOOLS_DIR}/qualimap_v2.2.1/qualimap"
PRESEQ_TOOL_DIR="${TOOLS_DIR}/preseq"
CONSERTING_SC_TOOL_DIR="${TOOLS_DIR}/Conserting_SC"

# hg38 reference files
REF_FASTA="${REFERENCE_DIR}/Homo_sapiens_assembly38.fasta"
REF_GENOME="${REFERENCE_DIR}/Homo_sapiens_assembly38_bedtools.genome" # .genome or .fai file produced from samtools faidx function
N25CHR_BED="${REFERENCE_DIR}/Homo_sapiens_assembly38_n25chr.bed"
KNOWN_SITES_VCFS=(
    "${REFERENCE_DIR}/Homo_sapiens_assembly38.dbsnp138.vcf.gz"
    "${REFERENCE_DIR}/Mills_and_1000G_gold_standard.indels.hg38.vcf.gz"
    "${REFERENCE_DIR}/Homo_sapiens_assembly38.known_indels.vcf.gz"
)

# hg19 version b37 reference files
if [ "$GENOME_VERSION" = "b37" ]; then
    REF_FASTA="${REFERENCE_DIR}/human_g1k_v37.fasta"
    REF_GENOME="${REFERENCE_DIR}/human_g1k_v37.genome"
    N25CHR_BED="${REFERENCE_DIR}/human_g1k_v37_n25chr.bed"
    KNOWN_SITES_VCFS=(
        "${REFERENCE_DIR}/dbsnp_138.b37.vcf.gz"
        "${REFERENCE_DIR}/Mills_and_1000G_gold_standard.indels.b37.vcf.gz"
        "${REFERENCE_DIR}/1000G_phase1.indels.b37.vcf.gz"
    )
fi

if [ $DUP_MARK_AGAIN -eq 0 ]; then
    echo "### Combining BAMs ### - START: $(date)"
    BAM_FILENAMES=( $(ls split_aligning_${SAMPLE}/${SAMPLE}_split_[0-9]*.bam) )
    if [ ${#BAM_FILENAMES[@]} -eq 1 ]; then # A single bam entry, so no merging is occurring
        mv ${BAM_FILENAMES[@]} ${SAMPLE}.bam
    else
        samtools merge ${SAMPLE}.bam ${BAM_FILENAMES[@]}
    fi
    samtools index ${SAMPLE}.bam
    echo "### Combining BAMs ### - END: $(date)"


    echo "### BAM Read Group Replacement - START: $(date) ###"
    gatk --java-options "-XX:+UseParallelGC -XX:ParallelGCThreads=4 -Xmx63g" AddOrReplaceReadGroups \
        -I ${SAMPLE}.bam -O ${SAMPLE}.rg.bam --VALIDATION_STRINGENCY LENIENT \
        -ID $SAMPLE -LB $SAMPLE -PL Illumina -PU $SAMPLE -SM $SAMPLE
    samtools index ${SAMPLE}.rg.bam ${SAMPLE}.rg.bam.bai
    echo "### BAM Read Group Replacement - END: $(date) ###"
fi


if [ $DUP_MARK_AGAIN -eq 0 ] && [ $RNA -eq 0 ]; then
    echo "### Base Quality Score Recalibration (BQSR) - START: $(date) ###"
    gatk --java-options "-XX:+UseParallelGC -XX:ParallelGCThreads=4 -Xmx63g" BaseRecalibrator \
        -R $REF_FASTA -I ${SAMPLE}.rg.bam --use-original-qualities \
        -O ${SAMPLE}.bqsr --known-sites $(echo ${KNOWN_SITES_VCFS[@]} | sed 's/ / --known-sites /g')
    echo "Computed recalibration"
    gatk --java-options "-XX:+UseParallelGC -XX:ParallelGCThreads=4 -Xmx63g" ApplyBQSR \
        -O ${SAMPLE}.bqsr.bam --create-output-bam-md5 --add-output-sam-program-record \
        -R $REF_FASTA -I ${SAMPLE}.rg.bam --use-original-qualities --bqsr ${SAMPLE}.bqsr \
        --static-quantized-quals 10 --static-quantized-quals 20 --static-quantized-quals 30
    echo "Applied recalibration"
    echo "### Base Quality Score Recaligbration (BQSR) - END: $(date) ###"
fi


if [ $MAPQ_MIN -ne 0 ] && [ $RNA -eq 0 ]; then
    echo "### Removing alignments with MAPQ value below $MAPQ_MIN - START: $(date) ###"
    mv ${SAMPLE}.bqsr.bam ${SAMPLE}.bqsr.all_mapqs.bam
    samtools view -h -b -q $MAPQ_MIN ${SAMPLE}.bqsr.all_mapqs.bam > ${SAMPLE}.bqsr.bam
    echo "### Removing alignments with MAPQ value below $MAPQ_MIN - END: $(date) ###"
fi


mv ${SAMPLE}.rg.bam ${SAMPLE}${BAM_SUFFIX}

# ml python/3.6.1
# export PYTHONPATH=/home/groups/cgawad/python_libs/lib/python3.6/site-packages:$PYTHONPATH
# export PATH=/home/groups/cgawad/python_libs/bin:$PATH
# 
# htseq-count -m intersection-nonempty -i gene_id -r pos -s no ${SAMPLE}${BAM_SUFFIX} /oak/stanford/groups/cgawad/Reference_Files/GATK_Resource_Bundle_hg38/gencode.v39.annotation.gtf
# htseq-count -m intersection-nonempty -i gene_id -r pos -s no ${SAMPLE}${BAM_SUFFIX} /oak/stanford/groups/cgawad/Reference_Files/GATK_Resource_Bundle_hg38/gencode.v39.annotation.gff3
# 
# if [ $DUPLICATE_PIXEL_DISTANCE -eq 0 ]; then
#     mv ${SAMPLE}.bqsr.bam ${SAMPLE}${BAM_SUFFIX}
# else
#     if [ $REMOVE_DUPS -eq 1 ]; then
#         REMOVE_DUPS="true"
#     else
#         REMOVE_DUPS="false"
#     fi
#     echo "### Marking Duplicates - START: $(date) ###"
#     # For OPTICAL_DUPLICATE_PIXEL_DISTANCE, 2500 is appropriate for patterned flow cells (e.g. NovaSeq, HiSeq). A value of 100 should be used for unpatterned flowcells (e.g. NextSeq, MiniSeq)
#     gatk --java-options "-XX:+UseParallelGC -XX:ParallelGCThreads=4 -Xmx63g" MarkDuplicates \
#         -I ${SAMPLE}.bqsr.bam -O ${SAMPLE}${BAM_SUFFIX} --METRICS_FILE ${SAMPLE}.duplication_metrics.tsv \
#         --VALIDATION_STRINGENCY SILENT --OPTICAL_DUPLICATE_PIXEL_DISTANCE $DUPLICATE_PIXEL_DISTANCE \
#         --ASSUME_SORT_ORDER coordinate --CLEAR_DT false --MAX_RECORDS_IN_RAM 1000 --ADD_PG_TAG_TO_READS false \
#         --REMOVE_DUPLICATES $REMOVE_DUPS
#     if [ ! -f ${SAMPLE}${BAM_SUFFIX} ]; then
#         echo "${SAMPLE}${BAM_SUFFIX} not found. Exiting with code 1"
#         exit 1
#     fi
#     echo "### Marking Duplicates - END: $(date) ###"
# fi


echo "### Indexing final BAM - START: $(date) ###"
samtools index ${SAMPLE}${BAM_SUFFIX}
echo "### Indexing final BAM - END: $(date) ###"


if [ $VARIANT_CLASS -eq 1 ]; then
    echo "### Basic bcftools variant calling - START: $(date) ###"
    samtools mpileup -uf $REF_FASTA ${SAMPLE}${BAM_SUFFIX} | bcftools call -mv > ${SAMPLE}.pileup_calls.vcf
	echo -e "count\tref\talt" > ${SAMPLE}.variant_class_counts.tsv
    cat ${SAMPLE}.pileup_calls.vcf | cut -f 4,5 | sort | uniq -c | sort -k1n | \
		sed 's/^[[:space:]]*//' | sed "s/ /$(printf '\t')/" >> ${SAMPLE}.variant_class_counts.tsv
	rm ${SAMPLE}.pileup_calls.vcf
    echo "### Basic bcftools variant calling - END: $(date) ###"
fi


echo "### Calculating QC metrics ### - START: $(date)"
gatk --java-options "-XX:+UseParallelGC -XX:ParallelGCThreads=4 -Xmx63g" CollectWgsMetrics \
    -I ${SAMPLE}${BAM_SUFFIX} -O ${SAMPLE}.wgs_metrics.tsv \
    -R $REF_FASTA --VALIDATION_STRINGENCY LENIENT --INTERVALS $INTERVAL_LIST
echo "CollectWgsMetrics done"

gatk --java-options "-XX:+UseParallelGC -XX:ParallelGCThreads=4 -Xmx63g" CollectMultipleMetrics \
    -I ${SAMPLE}${BAM_SUFFIX} -O ${SAMPLE}.multiple_metrics --INTERVALS $INTERVAL_LIST \
    -R $REF_FASTA --VALIDATION_STRINGENCY LENIENT --PROGRAM CollectAlignmentSummaryMetrics \
    --PROGRAM CollectBaseDistributionByCycle --PROGRAM CollectInsertSizeMetrics --PROGRAM MeanQualityByCycle \
    --PROGRAM QualityScoreDistribution --PROGRAM CollectGcBiasMetrics --FILE_EXTENSION .tsv
echo "CollectMultipleMetrics done"

gatk --java-options "-XX:+UseParallelGC -XX:ParallelGCThreads=4 -Xmx63g" CollectOxoGMetrics \
    -I ${SAMPLE}${BAM_SUFFIX} -O ${SAMPLE}.oxog_metrics.tsv -R $REF_FASTA \
    --VALIDATION_STRINGENCY LENIENT --INTERVALS $INTERVAL_LIST
echo "CollectOxoGMetrics done"

# cat <(samtools view -SH ${SAMPLE}${BAM_SUFFIX}) <(samtools view -S ${SAMPLE}${BAM_SUFFIX} | shuf -n 5000000) | samtools view -b - > ${SAMPLE}${BAM_5M_SUFFIX}
BAM_5M_SUFFIX=$(echo $BAM_SUFFIX | sed "s/.bam/.5M.bam/")
TOTAL_READS=$(samtools view -c ${SAMPLE}${BAM_SUFFIX})
FRACTION=$(awk -v y="$TOTAL_READS" 'BEGIN {printf "%3f", 5000000 / y}')
if [ $TOTAL_READS -ge 5000000 ] && [ ! -z $FRACTION ]; then
    gatk --java-options "-XX:+UseParallelGC -XX:ParallelGCThreads=4 -Xmx63g" DownsampleSam \
        -I ${SAMPLE}${BAM_SUFFIX} -O ${SAMPLE}${BAM_5M_SUFFIX} \
        --PROBABILITY $FRACTION --VALIDATION_STRINGENCY SILENT
    echo "5M downsample done"
    samtools index ${SAMPLE}${BAM_5M_SUFFIX}
    echo -e "chr\tstart\tend\tcovered_features\tcovered_bases\tbed_length\tbreadth_coverage_fraction" > ${SAMPLE}.wgs_5M_read_coverage.tsv
    bedtools coverage -g $REF_GENOME -sorted -a $N25CHR_BED -b ${SAMPLE}${BAM_5M_SUFFIX} >> ${SAMPLE}.wgs_5M_read_coverage.tsv
    echo "5 million read coverage done"

    samtools view -b -L $N25CHR_BED ${SAMPLE}${BAM_5M_SUFFIX} > ${SAMPLE}${BAM_5M_SUFFIX}.n25chr.bam
    $PRESEQ_TOOL_DIR/bam2mr -o ${SAMPLE}${BAM_5M_SUFFIX}.n25chr.mr ${SAMPLE}${BAM_5M_SUFFIX}.n25chr.bam
    $PRESEQ_TOOL_DIR/preseq gc_extrap -o ${SAMPLE}.gc_extrap.future_coverage_5M.tsv ${SAMPLE}${BAM_5M_SUFFIX}.n25chr.mr
    rm ${SAMPLE}${BAM_5M_SUFFIX}.n25chr.bam* ${SAMPLE}${BAM_5M_SUFFIX}.n25chr.mr
    if [ ! -f ${SAMPLE}.gc_extrap.future_coverage_5M.tsv ]; then
        echo "PreSeq for 5M encountered a problem and did not complete"
    else
        echo "PreSeq for 5M done"
    fi
else
    echo "Bam is less than 5 million reads, cannot downsample"
fi

if [ $TOTAL_READS -le 200000000 ]; then
    samtools view -b -L $N25CHR_BED ${SAMPLE}${BAM_SUFFIX} > ${SAMPLE}.bqsr.marked.n25chr.bam
    $PRESEQ_TOOL_DIR/bam2mr -o ${SAMPLE}.bqsr.marked.n25chr.mr ${SAMPLE}.bqsr.marked.n25chr.bam
    $PRESEQ_TOOL_DIR/preseq gc_extrap -o ${SAMPLE}.gc_extrap.future_coverage.tsv ${SAMPLE}.bqsr.marked.n25chr.mr
    rm ${SAMPLE}.bqsr.marked.n25chr.mr
    if [ ! -f ${SAMPLE}.gc_extrap.future_coverage.tsv ]; then
        echo "PreSeq encountered a problem and did not complete"
    else
        echo "PreSeq done"
    fi
else
    echo "BAM is larger than 200M reads. Will not compute PreSeq"
fi

samtools view -b -L $N25CHR_BED ${SAMPLE}${BAM_SUFFIX} > ${SAMPLE}.bqsr.marked.n25chr.bam
echo "Bam restriction to canonical 25 chr region done"
bedtools bamtobed -i ${SAMPLE}.bqsr.marked.n25chr.bam | cut -f 1-3 > ${SAMPLE}.bqsr.marked.n25chr.bed
echo "Bam to bed conversion done"
echo -e "chr\tstart\tend\tcovered_features\tcovered_bases\tbed_length\tbreadth_coverage_fraction" > ${SAMPLE}.wgs_coverage.tsv
bedtools coverage -g $REF_GENOME -sorted -a $N25CHR_BED -b ${SAMPLE}.bqsr.marked.n25chr.bed >> ${SAMPLE}.wgs_coverage.tsv
echo "Coverage done"

mkdir ${SAMPLE}_temp_qualimap_output
$QUALIMAP_TOOL bamqc -nt 4 -nw 3000 --java-mem-size=60G -bam ${SAMPLE}${BAM_SUFFIX} \
    -c -hm 3 -outdir ${SAMPLE}_temp_qualimap_output -outformat PDF
if [ ! -f ${SAMPLE}_temp_qualimap_output/report.pdf ]; then
    echo "QualiMap encountered a problem and did not complete"
else
    mv ${SAMPLE}_temp_qualimap_output/report.pdf ${SAMPLE}.multiple_metrics.qualimap_report.pdf
    mv ${SAMPLE}_temp_qualimap_output/genome_results.txt ${SAMPLE}.multiple_metrics.qualimap_genome_results.txt
    echo "QualiMap done"
fi
rm -r ${SAMPLE}_temp_qualimap_output
echo "### Calculating QC metrics ### - END: $(date)"


echo -e "END: $(date)\nRuntime: $(($(date +%s)-$START_TIME)) seconds"
if [ ! -f ${SAMPLE}${BAM_SUFFIX} ]; then
    echo "Final file ${SAMPLE}${BAM_SUFFIX} not found. Exiting with code 1"
    exit 1
fi
rm -r split_aligning_${SAMPLE}
rm ${SAMPLE}.bam* ${SAMPLE}.rg.bam* ${SAMPLE}.bqsr ${SAMPLE}.bqsr.bai ${SAMPLE}.bqsr.bam*
rm ${SAMPLE}.bqsr.marked.n25chr.bam* ${SAMPLE}.bqsr.marked.n25chr.bed