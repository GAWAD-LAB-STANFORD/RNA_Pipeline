#!/bin/bash
#
#SBATCH --job-name=submit_all
#SBATCH --mem=32G
#SBATCH --cpus-per-task=2
#SBATCH --time=5:00:00
#SBATCH --partition=cgawad

PIPELINE_DIR="$( cd "$( dirname "$0" )" && pwd )"
PIPELINE_COMMAND="$@"
HELP="\
Purpose: \n\t\
    To construct BAMs from RNA data from Whole Genome Sequencing pair-end fastq.gz files \n\n\
Required arguments: -p/--project <arg> and either -f/--fastq_dir <arg> or -r/--results_dir <arg> \n\
Optional arguments: -s/--scratch_dir <arg>, --err_out_dir <arg>, --skip_scratch, -b/--run_dir <arg>, \n\t\
    --sample_sheet <arg>, --R1_suffix <arg>, --R2_suffix <arg>, \n\t\
    --skip_trimming, --no_variant_class, --bam_suffix <arg>, \n\t\
    --exome, --panel_bed <arg>, --panel_interval_list <arg>, --slurm <arg> \n\
Defaults: \n\t\
    If no fastq_dir specified, uses results_dir \n\t\
    If no results_dir specified, makes new directory in fastq_dir \n\t\
    sample_sheet: SampleSheet.csv \n\t\
    R1_suffix: _L001_R1_001.fastq.gz or _R1_001.fastq.gz \n\t\
    R2_suffix: _L001_R2_001.fastq.gz or _R1_001.fastq.gz \n\t\
        
Defaults: \n\t\
    If no fastq_dir specified, uses results_dir \n\t\
    If no results_dir specified, makes new directory in fastq_dir \n\t\
    scratch_dir: /scratch/groups/cgawad/date_project_Scratch \n\t\
    sample_sheet: SampleSheet.csv \n\t\
    R1_suffix: _L001_R1_001.fastq.gz or _R1_001.fastq.gz or _R1.fastq.gz \n\t\
    R2_suffix: _L001_R2_001.fastq.gz or _R2_001.fastq.gz or _R2.fastq.gz \n\t\
    Runs WGS unless --exome specified \n\t\t\
        or unless --panel_bed <arg> and --panel_interval_list <arg> specified \n\t\
    Bam suffix: .rna.bam \n\t\t\
        or .rna.unmarked.bam when running with --skip_dup_mark \n\n\
Run after demultiplexing and with fastq directory: \n\t\
    sh ${PIPELINE_DIR}/submit_all.sh --fastq_dir /oak/stanford/groups/cgawad/2020-01-01_Fastqs/ --project 2020-01-01_Project \n\n\
Run after demultiplexing and with results directory: \n\t\
    sh ${PIPELINE_DIR}/submit_all.sh --fastq_dir /oak/stanford/groups/cgawad/2020-01-01_Fastqs/ --results_dir /oak/stanford/groups/cgawad/2020-01-01_Results/ --project 2020-01-01_Project \n\n\
Run with demultiplexing and fastq directory: \n\t\
    sh ${PIPELINE_DIR}/submit_all.sh --run_dir /oak/stanford/groups/cgawad/Illumina_Data/MiniSeq/2020-01-01_BCLs --fastq_dir /oak/stanford/groups/cgawad/2020-01-01_Fastqs/ --project 2020-01-01_Project \n\n\
Run with demultiplexing and results directory: \n\t\
    sh ${PIPELINE_DIR}/submit_all.sh --run_dir /oak/stanford/groups/cgawad/Illumina_Data/MiniSeq/2020-01-01_BCLs --results_dir /oak/stanford/groups/cgawad/2020-01-01_Results/ --project 2020-01-01_Project \n\n\
Run with demultiplexing, fastq directory, and results directory: \n\t\
    sh ${PIPELINE_DIR}/submit_all.sh --run_dir /oak/stanford/groups/cgawad/Illumina_Data/MiniSeq/2020-01-01_BCLs --fastq_dir /oak/stanford/groups/cgawad/2020-01-01_Fastqs/ --results_dir /oak/stanford/groups/cgawad/2020-01-01_Results/ --project 2020-01-01_Project \n\n\
For more information, read the README.md"

# Reads in command line option arguments and assigns them to variables
SKIP_SCRATCH=0
VARIANT_CLASS=1
BAM_SUFFIX=".rna.bam"
TARGETED=0
PANEL_BED=0
PANEL_INTERVAL_LIST=0
STEP=0
TEMP_ARRAY_START=0
DEPENDENCIES=()
while [ "$1" != "" ]; do
    case $1 in
        -h | --help )           echo -e $HELP
                                exit 0
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
        -s | --scratch_dir )    shift
                                SCRATCH_DIR=$1
                                ;;
        --err_out_dir )         shift
                                STD_ERR_OUT_DIR=$1
                                ;;
        --skip_scratch )        SKIP_SCRATCH=1
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
        --no_variant_class )    VARIANT_CLASS=0
                                ;;
        --bam_suffix )          shift
                                BAM_SUFFIX=$1
                                ;;
        --exome )               TARGETED=1
                                ;;
        --panel_bed )           shift
                                PANEL_BED=$1
                                ;;
        --panel_interval_list ) shift
                                PANEL_INTERVAL_LIST=$1
                                ;;
        --step1 )               STEP=1
                                ;;
        --step2 )               STEP=2
                                ;;
        --step3 )               STEP=3
                                ;;
        --temp_array_start )    shift
                                TEMP_ARRAY_START=$1
                                ;;
        --slurm )               shift
                                SLURM_OPTIONS=${@:1}
                                ;;
    esac
    shift
done

# Hardcoded paths and variables
READS_PER_SPLIT=5000000
TEMP_ARRAY_INCREMENT=1000
SCRIPT_DIR="${PIPELINE_DIR}/scripts"
TOOLS_DIR="/oak/stanford/groups/cgawad/Sequencing_Analysis_Tools"
PYTHON_LIBS="/home/groups/cgawad/python_libs/bin"
PYTHON_LIBS_SITE_PACKAGES="/home/groups/cgawad/python_libs/lib/python3.6/site-packages"
REFERENCE_DIR="/oak/stanford/groups/cgawad/Reference_Files/GATK_Resource_Bundle_hg38"
REF_FASTA="${REFERENCE_DIR}/Homo_sapiens_assembly38.fasta"
REF_GENOME="${REFERENCE_DIR}/Homo_sapiens_assembly38_bedtools.genome"
N25CHR_INTERVAL_LIST="${REFERENCE_DIR}/Homo_sapiens_assembly38_n25chr.interval_list"
N25CHR_BED="${REFERENCE_DIR}/Homo_sapiens_assembly38_n25chr.bed"

# Ensure we have the required variables set and set other variables
if ([ -z $FASTQ_DIR ] && [ -z $RESULTS_DIR ]) || [ -z $PROJECT ] || [ -z $PIPELINE_DIR ]; then
    echo "Variables not supplied correctly. Use -h/--help options for assistance. Ending program..."
    exit 1
fi
if [ -z $FASTQ_DIR ]; then
    FASTQ_DIR="$RESULTS_DIR"
elif [ -z $RESULTS_DIR ]; then
    RESULTS_DIR="${FASTQ_DIR}/$(date '+%Y-%m-%d')_${PROJECT}_Results"
fi
if [ -z $SCRATCH_DIR ] && [ $SKIP_SCRATCH -eq 0 ]; then
    SCRATCH_DIR="/scratch/groups/cgawad/$(date '+%Y-%m-%d')_${PROJECT}_Scratch"
elif [ $SKIP_SCRATCH -eq 1 ]; then
    SCRATCH_DIR="$RESULTS_DIR"
fi
if [ -z $STD_ERR_OUT_DIR ]; then
    STD_ERR_OUT_DIR="${RESULTS_DIR}/std_err_out_files"
fi
# Make directories if they don't exist
if [ ! -d $FASTQ_DIR ]; then
    mkdir $FASTQ_DIR
fi
if [ ! -d $RESULTS_DIR ]; then
    mkdir $RESULTS_DIR
fi
if [ ! -d $SCRATCH_DIR ]; then
    mkdir $SCRATCH_DIR
fi
if [ ! -d $STD_ERR_OUT_DIR ]; then
    mkdir $STD_ERR_OUT_DIR
fi
OPTIONS=( "-f $FASTQ_DIR -r $RESULTS_DIR -d $PIPELINE_DIR -p $PROJECT -s $SCRATCH_DIR --err_out_dir $STD_ERR_OUT_DIR " )
if [ ! -z $RUN_DIR ] && [ $ONLY_IDENTIFY -eq 1 ]; then
    echo "Variables not supplied correctly. Cannot perform demultiplexing while only identifying data. Exiting with code 1"
    exit 1
fi
if [ ! -z $RUN_DIR ] && [ -z $SAMPLE_SHEET ]; then
    SAMPLE_SHEET="${RUN_DIR}/SampleSheet.csv"
elif [ -z $RUN_DIR ] && [ ! -z $SAMPLE_SHEET ]; then
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
if [ $VARIANT_CLASS -eq 0 ]; then
    OPTIONS+=( "--no_variant_class" )
fi
if [ $BAM_SUFFIX != ".rna.bam" ]; then
    OPTIONS+=( "--bam_suffix $BAM_SUFFIX" )
fi
if [ "$PANEL_BED" != "0" ] && [ "$PANEL_INTERVAL_LIST" != "0" ]; then
    OPTIONS+=( "--panel_bed $PANEL_BED --panel_interval_list $PANEL_INTERVAL_LIST" )
    TARGETED=1
    TARGETS_BED=${PROJECT}.temporary_3_column_bed_interval_file.bed
    INTERVAL_LIST=$PANEL_INTERVAL_LIST
elif [ "$PANEL_BED" != "0" ] || [ "$PANEL_INTERVAL_LIST" != "0" ]; then
    echo "Variables not supplied correctly. Specify both --panel_bed and --panel_interval_list, or neither. Exiting with code 1"
    exit 1
else
    if [ $TARGETED -eq 1 ]; then
        OPTIONS+=( "--exome" )
        TARGETS_BED=$EXOME_TARGETS_BED
        INTERVAL_LIST=$EXOME_INTERVAL_LIST
    else
        TARGETS_BED=$N25CHR_BED
        INTERVAL_LIST=$N25CHR_INTERVAL_LIST
    fi
fi


TEMP_PIPELINE_DIR="$( cd "$( dirname "$0" )" && pwd )"
PIPELINE_STATUS=${STD_ERR_OUT_DIR}/${PROJECT}_pipeline_status.txt
cd $SCRATCH_DIR
if [ "$TEMP_PIPELINE_DIR" = "$PIPELINE_DIR" ]; then
    echo -e "\nSTART: $(date)\nRNA Pipeline\n\n$PIPELINE_COMMAND\n\nProject: $PROJECT\nResults dir: $RESULTS_DIR\nFastq dir: $FASTQ_DIR\nScratch dir: $SCRATCH_DIR\nErr out dir: $STD_ERR_OUT_DIR" >> $PIPELINE_STATUS
    if [ $SKIP_SCRATCH -eq 0 ]; then
        echo "Default: Scratch dir is different from Results dir" >> $PIPELINE_STATUS
    else
        echo "Option: Scratch dir is the same as Results dir" >> $PIPELINE_STATUS
    fi
    if [ "$PANEL_BED" != "0" ] && [ "$PANEL_INTERVAL_LIST" != "0" ]; then
        echo -e "Option: Custom gene panel\nOption: Panel bed: $PANEL_BED\nOption: Panel interval list: $PANEL_INTERVAL_LIST" >> $PIPELINE_STATUS
        cut -f 1,2,3 $PANEL_BED > $TARGETS_BED
    else
        if [ "$TARGETS_BED" = "$EXOME_TARGETS_BED" ]; then
            echo "Option: Whole Exome mode" >> $PIPELINE_STATUS
        elif [ $TARGETED -eq 1 ]; then
            echo "Option: Targeted mode" >> $PIPELINE_STATUS
        else
            echo "Default: Whole Genome mode" >> $PIPELINE_STATUS
        fi
    fi
    if [ $BAM_SUFFIX != ".bqsr.marked.bam" ]; then
        echo "Option: Bam suffix: $BAM_SUFFIX" >> $PIPELINE_STATUS
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


if ([ $STEP -eq 0 ] && [ -z $RUN_DIR ]) || [ $STEP -ne 0 ]; then
    if [ -z $R1_SUFFIX ] || [ -z $R2_SUFFIX ]; then
        R1_SUFFIX="_L001_R1_001.fastq.gz"
        R2_SUFFIX="_L001_R2_001.fastq.gz"
        if [ $(find ${FASTQ_DIR} -maxdepth 1 -name "*${R1_SUFFIX}" | wc -l) -eq 0 ]; then
            R1_SUFFIX="_R1_001.fastq.gz"
            R2_SUFFIX="_R2_001.fastq.gz"
        fi
        if [ $(find ${FASTQ_DIR} -maxdepth 1 -name "*${R1_SUFFIX}" | wc -l) -eq 0 ]; then
            R1_SUFFIX="_R1.fastq.gz"
            R2_SUFFIX="_R2.fastq.gz"
        fi
    fi
    SAMPLE_ARRAY=( $(find ${FASTQ_DIR} -maxdepth 1 -name "*${R1_SUFFIX}" -exec basename {} \; | \
        grep -v "Undetermined" | sed "s/${R1_SUFFIX}//") )
    if [ ${#SAMPLE_ARRAY[@]} -eq 0 ]; then
        echo "No fastq.gz files found in the fastq directory. Exiting with code 1"
        echo "No fastq.gz files found in the fastq directory. Exiting with code 1" >> $PIPELINE_STATUS
        echo "END: $(date)" >> $PIPELINE_STATUS
        exit 1
    fi
fi


if [ $STEP -eq 0 ] && [ ! -z $RUN_DIR ]; then
    echo "### Demultiplexing ### - START: $(date)" >> $PIPELINE_STATUS
    echo -e "Run dir: $RUN_DIR\nSample sheet: $SAMPLE_SHEET" >> $PIPELINE_STATUS
    DEPENDENCIES+=( $(sbatch --parsable -e ${STD_ERR_OUT_DIR}/%A_%x.err -o ${STD_ERR_OUT_DIR}/%A_%x.out \
        ${SCRIPT_DIR}/0_demultiplexer.sh --run_dir $RUN_DIR --sample_sheet $SAMPLE_SHEET --fastq_dir $FASTQ_DIR \
        --pipeline_status $PIPELINE_STATUS) )
    sbatch --dependency=afterok:${DEPENDENCIES[0]} -J $PROJECT \
        -e ${STD_ERR_OUT_DIR}/%A_submit_all_%x.err -o ${STD_ERR_OUT_DIR}/%A_submit_all_%x.out \
        ${PIPELINE_DIR}/submit_all.sh --step1 ${OPTIONS[@]}
elif ([ $STEP -eq 0 ] && [ -z $RUN_DIR ]) || [ $STEP -eq 1 ]; then
    if [ $TEMP_ARRAY_START -eq 0 ]; then
        echo -e "Number of samples: ${#SAMPLE_ARRAY[@]}\nSamples: ${SAMPLE_ARRAY[@]}\n" >> $PIPELINE_STATUS
        echo "### Splitting fastqs for parallelized alignment ### - START: $(date)" >> $PIPELINE_STATUS
        JOB_COUNT=${#SAMPLE_ARRAY[@]}
        echo -e "Reads per align job: $READS_PER_SPLIT\nJobs to run: $JOB_COUNT" >> $PIPELINE_STATUS
        TEMP_ARRAY_START=1
    fi
    
    TEMP_SAMPLE_ARRAY=( ${SAMPLE_ARRAY[@]:$(($TEMP_ARRAY_START - 1)):$TEMP_ARRAY_INCREMENT} )
    TEMP_JOB_COUNT=${#TEMP_SAMPLE_ARRAY[@]}
    echo "Submitting $TEMP_JOB_COUNT jobs for samples $TEMP_ARRAY_START to $(($TEMP_ARRAY_START + ${#TEMP_SAMPLE_ARRAY[@]} - 1))" >> $PIPELINE_STATUS
    TEMP_SAMPLES_STRING=$( IFS=$':'; echo "${TEMP_SAMPLE_ARRAY[*]}" )
    echo -e "\nsbatch --parsable -e $STD_ERR_OUT_DIR/%A_%a_%x.err -o $STD_ERR_OUT_DIR/%A_%a_%x.out \
        --array=1-${TEMP_JOB_COUNT} ${SCRIPT_DIR}/1_split_fastqs.sh \
        $FASTQ_DIR $SCRATCH_DIR $R1_SUFFIX $R2_SUFFIX $PYTHON_LIBS $PYTHON_LIBS_SITE_PACKAGES \
        $READS_PER_SPLIT $TEMP_SAMPLES_STRING\n" >> $PIPELINE_STATUS
    DEPENDENCIES+=( $(sbatch --parsable -e $STD_ERR_OUT_DIR/%A_%a_%x.err -o $STD_ERR_OUT_DIR/%A_%a_%x.out \
        --array=1-${TEMP_JOB_COUNT} ${SCRIPT_DIR}/1_split_fastqs.sh \
        $FASTQ_DIR $SCRATCH_DIR $R1_SUFFIX $R2_SUFFIX $PYTHON_LIBS $PYTHON_LIBS_SITE_PACKAGES \
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
        echo "### Splitting fastqs for parallelized alignment ### - END: $(date)" >> $PIPELINE_STATUS
        
        echo "### Aligning split fastqs ### - START: $(date)" >> $PIPELINE_STATUS
        FASTQ_ARRAY=()
        for SAMPLE in ${SAMPLE_ARRAY[@]}; do
            FASTQ_ARRAY+=( $(ls split_aligning_${SAMPLE}/${SAMPLE}_R1_split_[0-9]*.fastq) )
        done
        JOB_COUNT=${#FASTQ_ARRAY[@]}
        echo -e "Jobs to run: $JOB_COUNT" >> $PIPELINE_STATUS
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
        $SCRATCH_DIR $REF_FASTA $TOOLS_DIR $TEMP_FASTQ_STRING\n" >> $PIPELINE_STATUS
    DEPENDENCIES+=( $(sbatch --mem=64G --parsable -e $STD_ERR_OUT_DIR/%A_%a_%x.err -o $STD_ERR_OUT_DIR/%A_%a_%x.out \
        --array=1-${TEMP_JOB_COUNT} ${SCRIPT_DIR}/2_align_reads.sh \
        $SCRATCH_DIR $REF_FASTA $TOOLS_DIR $TEMP_FASTQ_STRING) )
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
        for SAMPLE in ${SAMPLE_ARRAY[@]}; do
            ALIGNED_BAMS_FOUND=$(echo $ALIGNED_BAMS_FOUND $(ls split_aligning_${SAMPLE}/${SAMPLE}_split_[0-9]*.bam | wc -l) | awk '{print $1 + $2 }')
        done
        if [ $ALIGNED_BAMS_FOUND -ne $JOB_COUNT ]; then
            echo "$ALIGNED_BAMS_FOUND BAM files found but expected $JOB_COUNT"
            echo "$ALIGNED_BAMS_FOUND BAM files found but expected $JOB_COUNT" >> $PIPELINE_STATUS
            echo -e "Exiting with code 1\nEND: $(date)" >> $PIPELINE_STATUS
            exit 1
        fi
        rm ${STD_ERR_OUT_DIR}/*2_align_reads.out ${STD_ERR_OUT_DIR}/*2_align_reads.err
        echo "### Aligning split fastqs ### - END: $(date)" >> $PIPELINE_STATUS
        
        echo "### Processing aligned fastqs into bams ### - START: $(date)" >> $PIPELINE_STATUS
        JOB_COUNT=${#SAMPLE_ARRAY[@]}
        echo "Jobs to run: $JOB_COUNT" >> $PIPELINE_STATUS
        TEMP_ARRAY_START=1
    fi
    
    TEMP_SAMPLE_ARRAY=( ${SAMPLE_ARRAY[@]:$(($TEMP_ARRAY_START - 1)):$TEMP_ARRAY_INCREMENT} )
    TEMP_JOB_COUNT=${#TEMP_SAMPLE_ARRAY[@]}
    echo "Submitting $TEMP_JOB_COUNT jobs for samples $TEMP_ARRAY_START to $(($TEMP_ARRAY_START + ${#TEMP_SAMPLE_ARRAY[@]} - 1))" >> $PIPELINE_STATUS
    TEMP_SAMPLES_STRING=$( IFS=$':'; echo "${TEMP_SAMPLE_ARRAY[*]}" )
    
    echo -e "\nsbatch --parsable -e $STD_ERR_OUT_DIR/%A_%a_%x.err -o $STD_ERR_OUT_DIR/%A_%a_%x.out \
        --array=1-${TEMP_JOB_COUNT} ${SCRIPT_DIR}/3_process_sample.sh \
        $SCRATCH_DIR $SCRIPT_DIR $TOOLS_DIR $REFERENCE_DIR $TEMP_SAMPLES_STRING \
        $BAM_SUFFIX $INTERVAL_LIST $VARIANT_CLASS\n" >> $PIPELINE_STATUS
    DEPENDENCIES+=( $(sbatch --parsable -e $STD_ERR_OUT_DIR/%A_%a_%x.err -o $STD_ERR_OUT_DIR/%A_%a_%x.out \
        --array=1-${TEMP_JOB_COUNT} ${SCRIPT_DIR}/3_process_sample.sh \
        $SCRATCH_DIR $SCRIPT_DIR $TOOLS_DIR $REFERENCE_DIR $TEMP_SAMPLES_STRING \
        $BAM_SUFFIX $INTERVAL_LIST $VARIANT_CLASS) )
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
elif [ $STEP -eq 4 ]; then
    SAMPLE_COUNT=1
    MISSING_COUNT=0
    MISSING_INDICES=""
    for SAMPLE in ${SAMPLE_ARRAY[@]}; do
        if [ ! -f ${SAMPLE}${BAM_SUFFIX} ]; then
            echo "Sample number $SAMPLE_COUNT - ${SAMPLE}${BAM_SUFFIX} file not found"
            echo "Sample number $SAMPLE_COUNT - ${SAMPLE}${BAM_SUFFIX} file not found" >> $PIPELINE_STATUS
            if [ $MISSING_COUNT -eq 0 ]; then
                MISSING_INDICES=$SAMPLE_COUNT
            else
                MISSING_INDICES="${MISSING_INDICES},${SAMPLE_COUNT}"
            fi
            MISSING_COUNT=$((MISSING_COUNT+1))
        fi
        SAMPLE_COUNT=$((SAMPLE_COUNT+1))
    done
    if [ ! -z "$REPEAT_SAMPLES" ]; then
        echo -e "Number bams missing: $MISSING_COUNT\nCommon causes:\
            1 - Demultiplexing error leading to unpaired reads in the FASTQ(s). \
            Demultiplexing will need to be done again\n\
            2 - Very large BAM(s) caused GATK's MarkDuplicates to run out of memory. \
            MarkDuplicates needs more memory or --MAX_RECORDS_IN_RAM needs to be reduced.\n\t\
            You can re-run with more memory if you replace \
            the beginning of the 3_process_sample.sh sbatch submission code with this code:" >> $PIPELINE_STATUS
        echo -e "\nsbatch --parsable -e $STD_ERR_OUT_DIR/%A_%a_%x.err -o $STD_ERR_OUT_DIR/%A_%a_%x.out \
            --array=${MISSING_INDICES} --cpus-per-task=6 ${SCRIPT_DIR}/3_process_sample.sh\n" >> $PIPELINE_STATUS
        echo "Exiting with code 1" >> $PIPELINE_STATUS
        echo "END: $(date)" >> $PIPELINE_STATUS
        exit 1
    fi
    echo "### Processing aligned fastqs into bams ### - END: $(date)" >> $PIPELINE_STATUS
    mkdir -p ${PROJECT}_Multiple_Metric_Files
    ml R/4.2.0 biology samtools
    export R_LIBS="/home/groups/cgawad/R_LIBS"
    bash ${SCRIPT_DIR}/summarize_metrics.sh $PIPELINE_STATUS $SCRIPT_DIR $PROJECT $RUN_DIR $SAMPLE_SHEET
    
    if [ "$SCRATCH_DIR" != "$RESULTS_DIR" ]; then
        echo "### Moving results from scratch dir to results dir ### - START: $(date)"
        rsync -ar $SCRATCH_DIR/ $RESULTS_DIR/
        echo "### Moving results from scratch dir to results dir ### - END: $(date)"
    fi
    echo "END: $(date)" >> $PIPELINE_STATUS
fi