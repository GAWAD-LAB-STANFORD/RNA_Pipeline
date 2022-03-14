#!/bin/bash
#
#SBATCH --job-name=submit_all
#SBATCH --cpus-per-task=1
#SBATCH --nodes=1
#SBATCH --time=5:00:00
#SBATCH --partition=cgawad

PIPELINE_DIR="$( cd "$( dirname "$0" )" && pwd )"
HELP="\
Purpose: \n\t\
    This pipeline is built to analyze RNA data from Whole Genome Sequencing pair-end fastq.gz files \n\n\
Required arguments: -p/--project <arg> and either -f/--fastq_dir <arg> or -r/--results_dir <arg> \n\
Optional arguments: -b/--run_dir <arg>, --sample_sheet <arg>, --R1_suffix <arg>, --R2_suffix <arg>, --err_out_dir <arg>, \n\t\
    --b37, --novaseq_wgs, --dup_mark_again, --skip_dup_mark, --remove_dups, \n\t\
    --dup_pixel_distance <arg>, --no_variant_class, --bam_suffix <arg>, --slurm <arg> \n\
Defaults: \n\t\
    If no fastq_dir specified, uses results_dir \n\t\
    If no results_dir specified, makes new directory in fastq_dir \n\t\
    sample_sheet: SampleSheet.csv \n\t\
    R1_suffix: _L001_R1_001.fastq.gz or _R1_001.fastq.gz \n\t\
    R2_suffix: _L001_R2_001.fastq.gz or _R1_001.fastq.gz \n\t\
    dup_pixel_distance: 100 \n\t\
    Bam suffix: .rna.bam \n\t\t\
        or .rna.unmarked.bam when running with --skip_dup_mark \n\n\
Run after demultiplexing: \n\t\
    sh ${PIPELINE_DIR}/submit_all.sh --fastq_dir /oak/stanford/groups/cgawad/MRD_project/ --project MRD_project \n\n\
Run with demultiplexing: \n\t\
    sh ${PIPELINE_DIR}/submit_all.sh --run_dir /oak/stanford/groups/cgawad/Illumina_Data/MiniSeq/191126_MN01236_0003_A000H2WWHT --fastq_dir /oak/stanford/groups/cgawad/MRD_project/ --project MRD_project \n\n\
For more information, read the README.md"

# Reads in command line option arguments and assigns them to variables
GENOME_VERSION=hg38
NOVASEQ_WGS=0
DUP_MARK_AGAIN=0
SKIP_DUPLICATE_MARKING=0
REMOVE_DUPS=0
DUPLICATE_PIXEL_DISTANCE=100
VARIANT_CLASS=1
BAM_SUFFIX=".rna.bam"
STEP=0
STEP3_REPEAT=0
TEMP_ARRAY_START=0
PREVIOUS_CHECK=0
DEPENDENCIES=()
while [ "$1" != "" ]; do
    case $1 in
        -h | --help )           echo -e $HELP
                                exit 0
                                ;;
        -b | --run_dir )        shift
                                RUN_DIR=$1
                                ;;
        --sample_sheet )        shift
                                SAMPLE_SHEET=$1
                                ;;
        --R1_suffix )           shift
                                R1_SUFFIX=$1
                                ;;
        --R2_suffix )           shift
                                R2_SUFFIX=$1
                                ;;
        --err_out_dir )         shift
                                STD_ERR_OUT_DIR=$1
                                ;;
        -f | --fastq_dir )      shift
                                FASTQ_DIR=$1
                                ;;
        -r | --results_dir )    shift
                                RESULTS_DIR=$1
                                ;;
        -p | --project )        shift
                                PROJECT=$1
                                ;;
        -d | --pipeline_dir )   shift
                                PIPELINE_DIR=$1
                                ;;
        --b37 )                 GENOME_VERSION=b37
                                ;;
        --novaseq_wgs )         NOVASEQ_WGS=1
                                ;;
        --dup_mark_again )      DUP_MARK_AGAIN=1
                                ;;
        --skip_dup_mark )       SKIP_DUPLICATE_MARKING=1
                                ;;
        --remove_dups )         REMOVE_DUPS=1
                                ;;
        --dup_pixel_distance )  shift
                                DUPLICATE_PIXEL_DISTANCE=$1
                                ;;
        --no_variant_class )    VARIANT_CLASS=0
                                ;;
        --bam_suffix )          shift
                                BAM_SUFFIX=$1
                                ;;
        --step1 )               STEP=1
                                ;;
        --step2 )               STEP=2
                                ;;
        --step3 )               STEP=3
                                ;;
        --step4 )               STEP=4
                                ;;
        --step3_repeat )        STEP3_REPEAT=1
                                ;;
        --temp_array_start )    shift
                                TEMP_ARRAY_START=$1
                                ;;
        --previous_check )      PREVIOUS_CHECK=1
                                ;;
        --slurm )               shift
                                SLURM_OPTIONS=${@:1}
                                ;;
    esac
    shift
done

# Hardcoded paths and variables
PYTHON_LIBS="/home/groups/cgawad/python_libs/bin"
PYTHON_LIBS_SITE_PACKAGES="/home/groups/cgawad/python_libs/lib/python3.6/site-packages"
READS_PER_SPLIT=5000000
TEMP_ARRAY_INCREMENT=1000
SCRIPT_DIR="${PIPELINE_DIR}/scripts"
TOOLS_DIR="/oak/stanford/groups/cgawad/Sequencing_Analysis_Tools"
ANNOVAR_DIR="/oak/stanford/groups/cgawad/Reference_Files/ANNOVAR"

# hg38 reference files
REFERENCE_DIR="/oak/stanford/groups/cgawad/Reference_Files/GATK_Resource_Bundle_hg38"
BISMARK_GENOME="/oak/stanford/groups/cgawad/Reference_Files/GATK_Resource_Bundle_hg38/Bismark"
REF_FASTA="${REFERENCE_DIR}/Homo_sapiens_assembly38.fasta"
REF_GENOME="${REFERENCE_DIR}/Homo_sapiens_assembly38_bedtools.genome"
N25CHR_INTERVAL_LIST="${REFERENCE_DIR}/Homo_sapiens_assembly38_n25chr.interval_list"
N25CHR_BED="${REFERENCE_DIR}/Homo_sapiens_assembly38_n25chr.bed"

# hg19 version b37 reference files
if [ "$GENOME_VERSION" = "b37" ]; then
    REFERENCE_DIR="/oak/stanford/groups/cgawad/Reference_Files/GATK_Resource_Bundle_b37"
    REF_FASTA="${REFERENCE_DIR}/human_g1k_v37.fasta"
    REF_GENOME="${REFERENCE_DIR}/human_g1k_v37.genome"
    N25CHR_INTERVAL_LIST="${REFERENCE_DIR}/human_g1k_v37_n25chr.interval_list"
    N25CHR_BED="${REFERENCE_DIR}/human_g1k_v37_n25chr.bed"
fi

# Ensure we have the requires variables set and set other variables
if ([ -z $FASTQ_DIR ] && [ -z $RESULTS_DIR ]) || [ -z $PROJECT ] || [ -z $PIPELINE_DIR ]; then
    echo "Variables not supplied correctly. Use -h/--help options for assistance. Exiting with code 1"
    exit 1
fi
if [ -z $FASTQ_DIR ]; then
    FASTQ_DIR="$RESULTS_DIR"
elif [ -z $RESULTS_DIR ]; then
    RESULTS_DIR="${FASTQ_DIR}/$(date '+%Y-%m-%d')_${PROJECT}_Results"
fi
if [ -z $STD_ERR_OUT_DIR ]; then
    STD_ERR_OUT_DIR="${RESULTS_DIR}/std_err_out_files"
fi
# Make results and std error output directories if they don't exist
if [ ! -d $FASTQ_DIR ]; then
    mkdir $FASTQ_DIR
fi
if [ ! -d $RESULTS_DIR ]; then
    mkdir $RESULTS_DIR
fi
if [ ! -d $STD_ERR_OUT_DIR ]; then
    mkdir $STD_ERR_OUT_DIR
fi
OPTIONS=( "--err_out_dir $STD_ERR_OUT_DIR -f $FASTQ_DIR -r $RESULTS_DIR -d $PIPELINE_DIR -p $PROJECT" )
if [ ! -z $RUN_DIR ] && [ -z $SAMPLE_SHEET ]; then
    SAMPLE_SHEET="${RUN_DIR}/SampleSheet.csv"
elif [ ! -z $SAMPLE_SHEET ]; then
    echo "Variables not supplied correctly. Please specify a run diretory for demultiplexing with --run_dir. Exiting with code 1"
    exit 1
fi
if [ ! -z $RUN_DIR ] && [ ! -z $SAMPLE_SHEET ]; then
    if [ ! -f $SAMPLE_SHEET ]; then
        echo "Sample sheet $SAMPLE_SHEET not found. Exiting with code 1"
        exit 1
    fi
    OPTIONS+=( "--run_dir $RUN_DIR --sample_sheet $SAMPLE_SHEET" )
fi
if [ ! -z $R1_SUFFIX ]; then
    OPTIONS+=( "--R1_suffix $R1_SUFFIX" )
fi
if [ ! -z $R2_SUFFIX ]; then
    OPTIONS+=( "--R2_suffix $R2_SUFFIX" )
fi
if [ "$GENOME_VERSION" = "b37" ]; then
    OPTIONS+=( "--b37" )
fi
if [ $NOVASEQ_WGS -eq 1 ]; then
    OPTIONS+=( "--novaseq_wgs" )
fi
if [ $DUP_MARK_AGAIN -eq 1 ]; then
    STEP=3
fi
if [ $SKIP_DUPLICATE_MARKING -eq 1 ]; then
    OPTIONS+=( "--skip_dup_mark" )
    DUPLICATE_PIXEL_DISTANCE=0
    if [ $BAM_SUFFIX == ".rna.bam" ]; then
        BAM_SUFFIX=".rna.unmarked.bam"
    fi
fi
if [ $REMOVE_DUPS -eq 1 ]; then
    OPTIONS+=( "--remove_dups" )
fi
if [ $DUPLICATE_PIXEL_DISTANCE -ne 100 ]; then
    OPTIONS+=( "--dup_pixel_distance $DUPLICATE_PIXEL_DISTANCE" )
fi
if [ $VARIANT_CLASS -eq 0 ]; then
    OPTIONS+=( "--no_variant_class" )
fi
if [ $BAM_SUFFIX != ".rna.bam" ]; then
    OPTIONS+=( "--bam_suffix $BAM_SUFFIX" )
fi
if [ $STEP3_REPEAT -eq 1 ]; then
    OPTIONS+=( "--step3_repeat" )
    DUP_MARK_AGAIN=1
    STEP=3
fi
if [ $STEP -eq 0 ] && [ -z $RUN_DIR ]; then
    STEP=1
fi


TEMP_PIPELINE_DIR="$( cd "$( dirname "$0" )" && pwd )"
PIPELINE_STATUS=${STD_ERR_OUT_DIR}/${PROJECT}_pipeline_status.txt
cd $RESULTS_DIR
if [ "$TEMP_PIPELINE_DIR" = "$PIPELINE_DIR" ]; then
    echo -e "\nSTART: $(date)\nRNA Pipeline\nErr out dir: $STD_ERR_OUT_DIR\nResults dir: $RESULTS_DIR\nProject: $PROJECT" >> $PIPELINE_STATUS
    if [ "$GENOME_VERSION" = "b37" ]; then
        echo "Option: Genome version hg19 subtype b37" >> $PIPELINE_STATUS
    else
        echo "Default: Genome version hg38" >> $PIPELINE_STATUS
    fi
    if [ $STEP3_REPEAT -eq 1 ]; then
        echo "Option: Step 3 processing samples being repeated once" >> $PIPELINE_STATUS
    fi
    echo "Fastq dir: $FASTQ_DIR" >> $PIPELINE_STATUS >> $PIPELINE_STATUS
    if [ ! -z $R1_SUFFIX ]; then
        echo "Option: R1 and R2 fastq pattern: $R1_SUFFIX $R2_SUFFIX" >> $PIPELINE_STATUS
    fi
    if [ $NOVASEQ_WGS -eq 1 ]; then
        echo "Option: Novaseq WGS -  Will add extra memory to certain jobs" >> $PIPELINE_STATUS
    fi
    if [ $DUP_MARK_AGAIN -eq 1 ]; then
        echo "Option: Starting from MarkDuplicates program" >> $PIPELINE_STATUS
    fi
    if [ $DUPLICATE_PIXEL_DISTANCE -eq 0 ]; then
        echo "Option: Skip marking of duplicates - will skip GATK MarkDuplicates" >> $PIPELINE_STATUS
    elif [ $DUPLICATE_PIXEL_DISTANCE -ne 100 ]; then
        echo "Option: Duplicate pixel distance changed to $DUPLICATE_PIXEL_DISTANCE" >> $PIPELINE_STATUS
    else
        echo "Default: Duplicate pixel distance: $DUPLICATE_PIXEL_DISTANCE" >> $PIPELINE_STATUS
    fi
    if [ $REMOVE_DUPS -eq 1 ]; then
        echo "Option: Removing duplicates in the BAM instead of marking them" >> $PIPELINE_STATUS
    fi
    if [ $VARIANT_CLASS -eq 0 ]; then
        OPTIONS+=( "--no_variant_class" )
    fi
    echo " " >> $PIPELINE_STATUS
fi


if [ ! -z $SLURM_OPTIONS ]; then
    echo "Option: Slurm - entire pipeline run will be queued with user parameters" >> $PIPELINE_STATUS
    sbatch -J $PROJECT ${SLURM_OPTIONS[@]} \
        -e ${STD_ERR_OUT_DIR}/%A_submit_all_%x.err -o ${STD_ERR_OUT_DIR}/%A_submit_all_%x.out \
        ${PIPELINE_DIR}/submit_all.sh ${OPTIONS[@]}
    exit 0
fi


if [ $STEP -ne 0 ]; then
    if [ -z $R1_SUFFIX ] || [ -z $R2_SUFFIX ]; then
        R1_SUFFIX="_L001_R1_001.fastq.gz"
        R2_SUFFIX="_L001_R2_001.fastq.gz"
        if [ $(find ${FASTQ_DIR} -maxdepth 1 -name "*${R1_SUFFIX}" | wc -l) -eq 0 ]; then
            R1_SUFFIX="_R1_001.fastq.gz"
            R2_SUFFIX="_R2_001.fastq.gz"
        fi
    fi
    SAMPLE_ARRAY=( $(find ${FASTQ_DIR} -maxdepth 1 -name "*${R1_SUFFIX}" -exec basename {} \; | \
        grep -v "Undetermined" | sed "s/${R1_SUFFIX}//") )
    if [ ${#SAMPLE_ARRAY[@]} -eq 0 ]; then
        echo "No fastq.gz files found in the fastq directory. Exiting with code 1"
        echo "No fastq.gz files found in the fastq directory. Exiting with code 1" >> $PIPELINE_STATUS
        echo -e "END: $(date)" >> $PIPELINE_STATUS
        exit 1
    fi
    if [ $STEP -eq 1 ]; then
        echo -e "Number of samples: ${#SAMPLE_ARRAY[@]}\nSamples: ${SAMPLE_ARRAY[@]}" >> $PIPELINE_STATUS
    fi
fi


if [ $STEP -eq 0 ]; then
    echo "### Fastq processing step 0 - Demultiplexing ### - START: $(date)" >> $PIPELINE_STATUS
    echo -e "Run dir: $RUN_DIR\nSample sheet: $SAMPLE_SHEET" >> $PIPELINE_STATUS
    DEPENDENCIES+=( $(sbatch --parsable -e ${STD_ERR_OUT_DIR}/%A_%x.err -o ${STD_ERR_OUT_DIR}/%A_%x.out \
        ${SCRIPT_DIR}/0_demultiplexer.sh --run_dir $RUN_DIR --sample_sheet $SAMPLE_SHEET --fastq_dir $FASTQ_DIR \
        --pipeline_status $PIPELINE_STATUS) )
    echo -e "\nsbatch --dependency=afterok:${DEPENDENCIES[0]} -J $PROJECT \
        -e ${STD_ERR_OUT_DIR}/%A_submit_all_%x.err -o ${STD_ERR_OUT_DIR}/%A_submit_all_%x.out \
        ${PIPELINE_DIR}/submit_all.sh --step1 ${OPTIONS[@]}\n" >> $PIPELINE_STATUS
    sbatch --dependency=afterok:${DEPENDENCIES[0]} -J $PROJECT \
        -e ${STD_ERR_OUT_DIR}/%A_submit_all_%x.err -o ${STD_ERR_OUT_DIR}/%A_submit_all_%x.out \
        ${PIPELINE_DIR}/submit_all.sh --step1 ${OPTIONS[@]}
elif [ $STEP -eq 1 ]; then
    if [ $TEMP_ARRAY_START -eq 0 ]; then
        echo "### Fastq processing step 1 - Splitting Fastqs ### - START: $(date)" >> $PIPELINE_STATUS
        JOB_COUNT=${#SAMPLE_ARRAY[@]}
        echo -e "Reads per align job: $READS_PER_SPLIT\nSplit jobs to run: $JOB_COUNT" >> $PIPELINE_STATUS
        TEMP_ARRAY_START=1
    fi
    
    TEMP_SAMPLE_ARRAY=( ${SAMPLE_ARRAY[@]:$(($TEMP_ARRAY_START - 1)):$TEMP_ARRAY_INCREMENT} )
    TEMP_JOB_COUNT=${#TEMP_SAMPLE_ARRAY[@]}
    echo "Submitting $TEMP_JOB_COUNT jobs for samples $TEMP_ARRAY_START to $(($TEMP_ARRAY_START + ${#TEMP_SAMPLE_ARRAY[@]} - 1))" >> $PIPELINE_STATUS
    TEMP_SAMPLES_STRING=$( IFS=$':'; echo "${TEMP_SAMPLE_ARRAY[*]}" )
    echo -e "\nsbatch --parsable -e $STD_ERR_OUT_DIR/%A_%a_%x.err -o $STD_ERR_OUT_DIR/%A_%a_%x.out \
        --array=1-${TEMP_JOB_COUNT} ${SCRIPT_DIR}/1_split_fastqs.sh \
        $FASTQ_DIR $RESULTS_DIR $R1_SUFFIX $R2_SUFFIX $PYTHON_LIBS $PYTHON_LIBS_SITE_PACKAGES \
        $READS_PER_SPLIT $TEMP_SAMPLES_STRING\n" >> $PIPELINE_STATUS
    DEPENDENCIES+=( $(sbatch --parsable -e $STD_ERR_OUT_DIR/%A_%a_%x.err -o $STD_ERR_OUT_DIR/%A_%a_%x.out \
        --array=1-${TEMP_JOB_COUNT} ${SCRIPT_DIR}/1_split_fastqs.sh \
        $FASTQ_DIR $RESULTS_DIR $R1_SUFFIX $R2_SUFFIX $PYTHON_LIBS $PYTHON_LIBS_SITE_PACKAGES \
        $READS_PER_SPLIT $TEMP_SAMPLES_STRING) )
    TEMP_ARRAY_START=$(($TEMP_ARRAY_START + $TEMP_ARRAY_INCREMENT))
    
    if [ $TEMP_ARRAY_START -le ${#SAMPLE_ARRAY[@]} ]; then
        echo -e "\nsbatch --dependency=afterany:$( IFS=$':'; echo "${DEPENDENCIES[*]}" ) -J $PROJECT \
            -e ${STD_ERR_OUT_DIR}/%A_submit_all_%x.err -o ${STD_ERR_OUT_DIR}/%A_submit_all_%x.out \
            ${PIPELINE_DIR}/submit_all.sh --step1 --temp_array_start $TEMP_ARRAY_START ${OPTIONS[@]}\n" >> $PIPELINE_STATUS
        sbatch --dependency=afterany:$( IFS=$':'; echo "${DEPENDENCIES[*]}" ) -J $PROJECT \
            -e ${STD_ERR_OUT_DIR}/%A_submit_all_%x.err -o ${STD_ERR_OUT_DIR}/%A_submit_all_%x.out \
            ${PIPELINE_DIR}/submit_all.sh --step1 --temp_array_start $TEMP_ARRAY_START ${OPTIONS[@]}
    else
        echo -e "\nsbatch --dependency=afterany:$( IFS=$':'; echo "${DEPENDENCIES[*]}" ) -J $PROJECT \
            -e ${STD_ERR_OUT_DIR}/%A_submit_all_%x.err -o ${STD_ERR_OUT_DIR}/%A_submit_all_%x.out \
            ${PIPELINE_DIR}/submit_all.sh --step2 ${OPTIONS[@]}\n" >> $PIPELINE_STATUS
        sbatch --dependency=afterany:$( IFS=$':'; echo "${DEPENDENCIES[*]}" ) -J $PROJECT \
            -e ${STD_ERR_OUT_DIR}/%A_submit_all_%x.err -o ${STD_ERR_OUT_DIR}/%A_submit_all_%x.out \
            ${PIPELINE_DIR}/submit_all.sh --step2 ${OPTIONS[@]}
    fi
elif [ $STEP -eq 2 ]; then
    if [ $TEMP_ARRAY_START -eq 0 ]; then
        SAMPLE_COUNT=1
        for SAMPLE in ${SAMPLE_ARRAY[@]}; do
            if [ ! -d split_aligning_${SAMPLE} ]; then
                echo "Sample number $SAMPLE_COUNT - split_aligning_${SAMPLE} directory not found. Exiting with code 1"
                echo "Sample number $SAMPLE_COUNT - split_aligning_${SAMPLE} directory not found. Exiting with code 1" >> $PIPELINE_STATUS
                echo -e "END: $(date)" >> $PIPELINE_STATUS
                exit 1
            fi
            SAMPLE_COUNT=$((SAMPLE_COUNT+1))
        done
        rm ${STD_ERR_OUT_DIR}/*1_split_fastqs.out ${STD_ERR_OUT_DIR}/*1_split_fastqs.err
        echo "### Fastq processing step 1 - Splitting Fastqs ### - END: $(date)" >> $PIPELINE_STATUS
        
        echo "### Fastq processing step 2 - Aligning Fastqs ### - START: $(date)" >> $PIPELINE_STATUS
        FASTQ_ARRAY=()
        for SAMPLE in ${SAMPLE_ARRAY[@]}; do
            FASTQ_ARRAY+=( $(ls split_aligning_${SAMPLE}/${SAMPLE}_R1_split_[0-9]*.fastq) )
        done
        JOB_COUNT=${#FASTQ_ARRAY[@]}
        echo -e "Align jobs to run: $JOB_COUNT" >> $PIPELINE_STATUS
        TEMP_ARRAY_START=1
    fi
    FASTQ_ARRAY=()
    for SAMPLE in ${SAMPLE_ARRAY[@]}; do
        FASTQ_ARRAY+=( $(ls split_aligning_${SAMPLE}/${SAMPLE}_R1_split_[0-9]*.fastq) )
    done
    
    TEMP_FASTQ_ARRAY=( ${FASTQ_ARRAY[@]:$(($TEMP_ARRAY_START - 1)):$TEMP_ARRAY_INCREMENT} )
    TEMP_JOB_COUNT=${#TEMP_FASTQ_ARRAY[@]}
    echo "Submitting $TEMP_JOB_COUNT jobs for fastqs $TEMP_ARRAY_START to $(($TEMP_ARRAY_START + ${#TEMP_FASTQ_ARRAY[@]} - 1))" >> $PIPELINE_STATUS
    TEMP_FASTQ_STRING=$( IFS=$':'; echo "${TEMP_FASTQ_ARRAY[*]}" )
    echo -e "\nsbatch --mem=64G --parsable -e $STD_ERR_OUT_DIR/%A_%a_%x.err -o $STD_ERR_OUT_DIR/%A_%a_%x.out \
        --array=1-${TEMP_JOB_COUNT} ${SCRIPT_DIR}/2_align_reads.sh \
        $RESULTS_DIR $REF_FASTA $TOOLS_DIR $TEMP_FASTQ_STRING\n" >> $PIPELINE_STATUS
    DEPENDENCIES+=( $(sbatch --mem=64G --parsable -e $STD_ERR_OUT_DIR/%A_%a_%x.err -o $STD_ERR_OUT_DIR/%A_%a_%x.out \
        --array=1-${TEMP_JOB_COUNT} ${SCRIPT_DIR}/2_align_reads.sh \
        $RESULTS_DIR $REF_FASTA $TOOLS_DIR $TEMP_FASTQ_STRING) )
    TEMP_ARRAY_START=$(($TEMP_ARRAY_START + $TEMP_ARRAY_INCREMENT))
    echo "New start: $TEMP_ARRAY_START"
    echo "Increment: $TEMP_ARRAY_INCREMENT"
    
    if [ $TEMP_ARRAY_START -le ${#FASTQ_ARRAY[@]} ]; then
        echo -e "\nsbatch --dependency=afterany:$( IFS=$':'; echo "${DEPENDENCIES[*]}" ) -J $PROJECT \
            -e ${STD_ERR_OUT_DIR}/%A_submit_all_%x.err -o ${STD_ERR_OUT_DIR}/%A_submit_all_%x.out \
            ${PIPELINE_DIR}/submit_all.sh --step2 --temp_array_start $TEMP_ARRAY_START ${OPTIONS[@]}\n" >> $PIPELINE_STATUS
        sbatch --dependency=afterany:$( IFS=$':'; echo "${DEPENDENCIES[*]}" ) -J $PROJECT \
            -e ${STD_ERR_OUT_DIR}/%A_submit_all_%x.err -o ${STD_ERR_OUT_DIR}/%A_submit_all_%x.out \
            ${PIPELINE_DIR}/submit_all.sh --step2 --temp_array_start $TEMP_ARRAY_START ${OPTIONS[@]}
    else
        echo -e "\nsbatch --dependency=afterany:$( IFS=$':'; echo "${DEPENDENCIES[*]}" ) -J $PROJECT \
            -e ${STD_ERR_OUT_DIR}/%A_submit_all_%x.err -o ${STD_ERR_OUT_DIR}/%A_submit_all_%x.out \
            ${PIPELINE_DIR}/submit_all.sh --step3 ${OPTIONS[@]}\n" >> $PIPELINE_STATUS
        sbatch --dependency=afterany:$( IFS=$':'; echo "${DEPENDENCIES[*]}" ) -J $PROJECT \
            -e ${STD_ERR_OUT_DIR}/%A_submit_all_%x.err -o ${STD_ERR_OUT_DIR}/%A_submit_all_%x.out \
            ${PIPELINE_DIR}/submit_all.sh --step3 ${OPTIONS[@]}
    fi
elif [ $STEP -eq 3 ]; then
    if [ $TEMP_ARRAY_START -eq 0 ]; then
        FASTQ_ARRAY=()
        for SAMPLE in ${SAMPLE_ARRAY[@]}; do
            FASTQ_ARRAY+=( $(ls split_aligning_${SAMPLE}/${SAMPLE}_R1_split_[0-9]*.fastq) )
        done
        JOB_COUNT=${#FASTQ_ARRAY[@]}
        ALIGNED_BAMS_FOUND=0
        STEP_FAILED=0
        for SAMPLE in ${SAMPLE_ARRAY[@]}; do
            ALIGNED_BAMS_FOUND=$(echo $ALIGNED_BAMS_FOUND $(ls split_aligning_${SAMPLE}/${SAMPLE}_split_[0-9]*.bam | wc -l) | awk '{print $1 + $2 }')
        done
        if [ $ALIGNED_BAMS_FOUND -ne $JOB_COUNT ]; then
            echo "$ALIGNED_BAMS_FOUND BAM files found but expected $JOB_COUNT"
            echo "$ALIGNED_BAMS_FOUND BAM files found but expected $JOB_COUNT" >> $PIPELINE_STATUS
            STEP_FAILED=1
        fi
        if [ $STEP_FAILED -eq 1 ]; then
            echo -e "Exiting with code 1\nEND: $(date)" >> $PIPELINE_STATUS
            exit 1
        fi
        rm ${STD_ERR_OUT_DIR}/*2_align_reads.out ${STD_ERR_OUT_DIR}/*2_align_reads.err
        echo "### Fastq processing step 2 - Aligning Fastqs ### - END: $(date)" >> $PIPELINE_STATUS
        
        echo "### Fastq processing step 3 - Processing samples ### - START: $(date)" >> $PIPELINE_STATUS
        JOB_COUNT=${#SAMPLE_ARRAY[@]}
        echo "Process sample jobs to run: $JOB_COUNT" >> $PIPELINE_STATUS
        TEMP_ARRAY_START=1
    fi
    
    TEMP_SAMPLE_ARRAY=( ${SAMPLE_ARRAY[@]:$(($TEMP_ARRAY_START - 1)):$TEMP_ARRAY_INCREMENT} )
    TEMP_JOB_COUNT=${#TEMP_SAMPLE_ARRAY[@]}
    echo "Submitting $TEMP_JOB_COUNT jobs for samples $TEMP_ARRAY_START to $(($TEMP_ARRAY_START + ${#TEMP_SAMPLE_ARRAY[@]} - 1))" >> $PIPELINE_STATUS
    TEMP_SAMPLES_STRING=$( IFS=$':'; echo "${TEMP_SAMPLE_ARRAY[*]}" )
    if [ $NOVASEQ_WGS -eq 1 ]; then
        echo -e "\nsbatch --parsable -e $STD_ERR_OUT_DIR/%A_%a_%x.err -o $STD_ERR_OUT_DIR/%A_%a_%x.out \
            --array=1-${TEMP_JOB_COUNT} ${SCRIPT_DIR}/3_process_sample.sh --cpus-per-task=6 \
            $RESULTS_DIR $GENOME_VERSION $SCRIPT_DIR $TOOLS_DIR $REFERENCE_DIR $TEMP_SAMPLES_STRING $DUP_MARK_AGAIN \
            $DUPLICATE_PIXEL_DISTANCE $REMOVE_DUPS $BAM_SUFFIX $INTERVAL_LIST $VARIANT_CLASS\n" >> $PIPELINE_STATUS
        DEPENDENCIES+=( $(sbatch --parsable -e $STD_ERR_OUT_DIR/%A_%a_%x.err -o $STD_ERR_OUT_DIR/%A_%a_%x.out \
            --array=1-${TEMP_JOB_COUNT} ${SCRIPT_DIR}/3_process_sample.sh --cpus-per-task=6 \
            $RESULTS_DIR $GENOME_VERSION $SCRIPT_DIR $TOOLS_DIR $REFERENCE_DIR $TEMP_SAMPLES_STRING $DUP_MARK_AGAIN \
            $DUPLICATE_PIXEL_DISTANCE $REMOVE_DUPS $BAM_SUFFIX $INTERVAL_LIST $VARIANT_CLASS) )
    elif [ $DUP_MARK_AGAIN -eq 1 ]; then
        SAMPLE_COUNT=1
        REPEAT_SAMPLES=""
        for SAMPLE in ${SAMPLE_ARRAY[@]}; do
            if [ ! -f ${SAMPLE}${BAM_SUFFIX} ]; then
                if [ -z "$REPEAT_SAMPLES" ]; then
                    REPEAT_SAMPLES=$SAMPLE_COUNT
                else
                    REPEAT_SAMPLES="${REPEAT_SAMPLES},${SAMPLE_COUNT}"
                fi
            fi
            SAMPLE_COUNT=$((SAMPLE_COUNT+1))
        done
        echo -e "\nsbatch --parsable -e $STD_ERR_OUT_DIR/%A_%a_%x.err -o $STD_ERR_OUT_DIR/%A_%a_%x.out \
            --array=${REPEAT_SAMPLES} ${SCRIPT_DIR}/3_process_sample.sh --cpus-per-task=6 \
            $RESULTS_DIR $GENOME_VERSION $SCRIPT_DIR $TOOLS_DIR $REFERENCE_DIR $TEMP_SAMPLES_STRING $DUP_MARK_AGAIN \
            $DUPLICATE_PIXEL_DISTANCE $REMOVE_DUPS $BAM_SUFFIX $INTERVAL_LIST $VARIANT_CLASS\n" >> $PIPELINE_STATUS
        DEPENDENCIES+=( $(sbatch --parsable -e $STD_ERR_OUT_DIR/%A_%a_%x.err -o $STD_ERR_OUT_DIR/%A_%a_%x.out \
            --array=${REPEAT_SAMPLES} ${SCRIPT_DIR}/3_process_sample.sh --cpus-per-task=6 \
            $RESULTS_DIR $GENOME_VERSION $SCRIPT_DIR $TOOLS_DIR $REFERENCE_DIR $TEMP_SAMPLES_STRING $DUP_MARK_AGAIN \
            $DUPLICATE_PIXEL_DISTANCE $REMOVE_DUPS $BAM_SUFFIX $INTERVAL_LIST $VARIANT_CLASS) )
    else
        echo -e "\nsbatch --parsable -e $STD_ERR_OUT_DIR/%A_%a_%x.err -o $STD_ERR_OUT_DIR/%A_%a_%x.out \
            --array=1-${TEMP_JOB_COUNT} ${SCRIPT_DIR}/3_process_sample.sh \
            $RESULTS_DIR $GENOME_VERSION$SCRIPT_DIR $TOOLS_DIR $REFERENCE_DIR $TEMP_SAMPLES_STRING $DUP_MARK_AGAIN \
            $DUPLICATE_PIXEL_DISTANCE $REMOVE_DUPS $BAM_SUFFIX $INTERVAL_LIST $VARIANT_CLASS\n" >> $PIPELINE_STATUS
        DEPENDENCIES+=( $(sbatch --parsable -e $STD_ERR_OUT_DIR/%A_%a_%x.err -o $STD_ERR_OUT_DIR/%A_%a_%x.out \
            --array=1-${TEMP_JOB_COUNT} ${SCRIPT_DIR}/3_process_sample.sh \
            $RESULTS_DIR $GENOME_VERSION$SCRIPT_DIR $TOOLS_DIR $REFERENCE_DIR $TEMP_SAMPLES_STRING $DUP_MARK_AGAIN \
            $DUPLICATE_PIXEL_DISTANCE $REMOVE_DUPS $BAM_SUFFIX $INTERVAL_LIST $VARIANT_CLASS) )
    fi
    TEMP_ARRAY_START=$(($TEMP_ARRAY_START + $TEMP_ARRAY_INCREMENT))
    
    if [ $TEMP_ARRAY_START -le ${#SAMPLE_ARRAY[@]} ]; then
        echo -e "\nsbatch --dependency=afterany:$( IFS=$':'; echo "${DEPENDENCIES[*]}" ) -J $PROJECT \
            -e ${STD_ERR_OUT_DIR}/%A_submit_all_%x.err -o ${STD_ERR_OUT_DIR}/%A_submit_all_%x.out \
            ${PIPELINE_DIR}/submit_all.sh --step3 --temp_array_start $TEMP_ARRAY_START ${OPTIONS[@]}\n" >> $PIPELINE_STATUS
        sbatch --dependency=afterany:$( IFS=$':'; echo "${DEPENDENCIES[*]}" ) -J $PROJECT \
            -e ${STD_ERR_OUT_DIR}/%A_submit_all_%x.err -o ${STD_ERR_OUT_DIR}/%A_submit_all_%x.out \
            ${PIPELINE_DIR}/submit_all.sh --step3 --temp_array_start $TEMP_ARRAY_START ${OPTIONS[@]}
    else
        echo -e "\nsbatch --dependency=afterany:$( IFS=$':'; echo "${DEPENDENCIES[*]}" ) -J $PROJECT \
            -e ${STD_ERR_OUT_DIR}/%A_submit_all_%x.err -o ${STD_ERR_OUT_DIR}/%A_submit_all_%x.out \
            ${PIPELINE_DIR}/submit_all.sh --step4 --previous_check ${OPTIONS[@]}\n" >> $PIPELINE_STATUS
        sbatch --dependency=afterany:$( IFS=$':'; echo "${DEPENDENCIES[*]}" ) -J $PROJECT \
            -e ${STD_ERR_OUT_DIR}/%A_submit_all_%x.err -o ${STD_ERR_OUT_DIR}/%A_submit_all_%x.out \
            ${PIPELINE_DIR}/submit_all.sh --step4 --previous_check ${OPTIONS[@]}
    fi
elif [ $STEP -eq 4 ] && [ $PREVIOUS_CHECK -eq 1 ]; then
    SAMPLE_COUNT=1
    STEP_FAILED=0
    for SAMPLE in ${SAMPLE_ARRAY[@]}; do
        if [ ! -f ${SAMPLE}${BAM_SUFFIX} ]; then
            echo "Sample number $SAMPLE_COUNT - ${SAMPLE}${BAM_SUFFIX} file not found"
            echo "Sample number $SAMPLE_COUNT - ${SAMPLE}${BAM_SUFFIX} file not found" >> $PIPELINE_STATUS
            STEP_FAILED=1
        fi
        SAMPLE_COUNT=$((SAMPLE_COUNT+1))
    done
    if [ $STEP_FAILED -eq 1 ] && [ $STEP3_REPEAT -eq 0 ]; then
        echo "Common causes:" >> $PIPELINE_STATUS
        echo "1 - Demultiplexing error leading to unpaired reads in the FASTQ(s). Demultiplexing will need to be done again" >> $PIPELINE_STATUS
        echo "2 - Very large BAM(s) caused GATK's MarkDuplicates to run out of memory. --MAX_RECORDS_IN_RAM will need to be reduced" >> $PIPELINE_STATUS
        if [ $STEP3_REPEAT -eq 0 ]; then
            echo "Will re-run step 3 once with 6 instead of 4 CPUs." >> $PIPELINE_STATUS
            echo -e "\nsbatch --dependency=afterany:$( IFS=$':'; echo "${DEPENDENCIES[*]}" ) -J $PROJECT \
                -e ${STD_ERR_OUT_DIR}/%A_submit_all_%x.err -o ${STD_ERR_OUT_DIR}/%A_submit_all_%x.out \
                ${PIPELINE_DIR}/submit_all.sh --step3_repeat --step3 ${OPTIONS[@]}\n" >> $PIPELINE_STATUS
            sbatch --dependency=afterany:$( IFS=$':'; echo "${DEPENDENCIES[*]}" ) -J $PROJECT \
                -e ${STD_ERR_OUT_DIR}/%A_submit_all_%x.err -o ${STD_ERR_OUT_DIR}/%A_submit_all_%x.out \
                ${PIPELINE_DIR}/submit_all.sh --step3_repeat --step3 ${OPTIONS[@]}
        fi
        echo "Exiting with code 1." >> $PIPELINE_STATUS
        echo -e "END: $(date)" >> $PIPELINE_STATUS
        exit 1
    fi
    PREVIOUS_CHECK=0
    echo "### Fastq processing step 3 - Processing samples ### - END: $(date)" >> $PIPELINE_STATUS
    mkdir -p ${PROJECT}_Multiple_Metric_Files
    echo -e "\nsbatch -e $STD_ERR_OUT_DIR/%A_%x.err -o $STD_ERR_OUT_DIR/%A_%x.out \
        ${SCRIPT_DIR}/summarize_metrics.sh $RESULTS_DIR $SCRIPT_DIR $PROJECT $RUN_DIR $SAMPLE_SHEET\n" >> $PIPELINE_STATUS
    sbatch -e $STD_ERR_OUT_DIR/%A_%x.err -o $STD_ERR_OUT_DIR/%A_%x.out \
        ${SCRIPT_DIR}/summarize_metrics.sh $RESULTS_DIR $SCRIPT_DIR $PROJECT $RUN_DIR $SAMPLE_SHEET
    echo "Submitted asynchronous summarize metrics job" >> $PIPELINE_STATUS
fi


if [ $STEP -eq 4 ]; then
    SAMPLE_ARRAY=( $(ls *${BAM_SUFFIX} | sed "s/${BAM_SUFFIX}//") )
    if [ ${#SAMPLE_ARRAY[@]} -eq 0 ]; then
        echo "No BAM files found in the results directory. Exiting with code 1"
        echo "No BAM files found in the results directory. Exiting with code 1" >> $PIPELINE_STATUS
        echo -e "END: $(date)" >> $PIPELINE_STATUS
        exit 1
    fi
    echo "END: $(date)"
fi