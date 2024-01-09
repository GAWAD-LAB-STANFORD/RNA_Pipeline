# Guide to RNA_Pipeline

- [Purpose](#purpose)
- [How To Run](#how-to-run)
- [What It Does Exactly](#what-it-does-exactly)

## Purpose
- This pipeline is built to analyze RNA data from Whole Genome Sequencing pair-end fastq.gz files

## How To Run
- All scripts are controlled by the master script, pipeline_control.sh
- To make job submission easier, use the submit_all.sh script to submit the master script
    - For help, use the *-h* or *--help* option like:

    ```bash
    sh submit_all.sh --help
    ```

- You can use ~ if your file or folder is in your home directory, and you can exclude a path if your file or folder is in the results directory, but otherwise use absolute paths
- You can have '/' or nothing at the end of a directory path, either is fine:
    - -r /home/groups/cgawad/results/
    - -r /home/groups/cgawad/results

### submit_all.sh
- **Run this script in order to run the entire pipeline**
- Required arguments: -p/--project >arg< and either -f/--fastq_dir >arg< or -r/--results_dir >arg<
    - Specify where your fastq.gz files are located (or will be put after you opt for the auto-demultiplexing) using *-f* or *--fastq_dir* and/or specify where to output the results using *-r* or *--results_dir*
        - If you do not specify a fastq directory, the program will assume the fastq.gz files are in the results directory you specified, and will end the program if no fastq.gz files are found
        - If you do not specify a results directory, the program will make a new folder with the current date in the name within the fastq directory 
    - Specify the project name for the final resulting VCF that will be made using *-p* or *--project*
- Optional arguments: -s/--scratch_dir >arg<, --err_out_dir >arg<, --skip_scratch, -b/--run_dir >arg<, --sample_sheet >arg<, --R1_suffix >arg<, --R2_suffix >arg<, --skip_trimming, --no_variant_class, --bam_suffix >arg<, --exome, --panel_bed >arg<, --panel_interval_list >arg<, --slurm >arg<
    - If you want to specify a directory to perform all intermediate steps in, specify with *-s* or *--scratch_dir*
    - If you want to specify a directory to output the standard error and out print statements of all jobs to, specify with *--err_out_dir*
    - If you want to skip having the pipeline run intermediate steps in scratch, use *--skip_scratch*
    - If you want the script to demultiplex your BCL files into fastq.gz files, specify the run folder with *-b* or *--run_dir*. The program will look for a sample sheet called SampleSheet.csv in the first level within the run_dir or you can specify a different sample sheet with *--sample_sheet*. The program will make the fastq directory if it does not exist and tell you the sizes of undeteremined vs fully demultiplexed reads
    - If you don't want trimmomatic to run, add the *--skip_trimming* option
    - If you want to skip the slow summing of variant classes that gets performed by default using samtools pileup and bcftools then add the option *--no_variant_class*
    - If your BAMs do not end in ".bqsr.marked.bam" then specify their suffix with the option *--bam_suffix* followed by your BAM suffix
    - If your data is whole exome sequencing instead of the default assumption of whole genome sequencing, add the option *--exome*
    - If you want to further restrict the analysis to a smaller subset of genes than whole exome sequencing, you need to provide a bed file and interval list file using *--panel_bed* and *--panel_interval_list*
    - Besides the already implemented job name and standard error and output print statements, you can specify additional slurm commands for the pipeline job following the use of the option *--slurm*. If you use this option, **make sure it is the last one you use**
        - A useful example would be setting a future time to run the job and asking for email notifications like so:

        ```
        ... --slurm --begin=now+12hours --mail-type=ALL 
        ```

- Get some example submissions by using *-h* or *--help* options like:

    ```bash
    sh submit_all.sh --help
    ```

## What It Does Exactly

![Pipeline Graphic](pipeline_graphic.png)

### submit_all.sh
- **0_demultiplexer.sh** - Demultiplexing will be done if specified
- **1_split_fastqs.sh** - For each sample, a job will be run to do the following:
    - If a UMI pattern or file of cell barcodes is supplied, the reads will be extracted according to their UMI pattern or cell barcode
        - Extraction metrics will also be calculated
    - Split the fastqs into smaller fastqs of 5 million reads per fastq
    - Count the reads before trimming, the reads left after trimming, and the reads that were removed after trimming
- **2_align_reads.sh** - For each split fastq, a job will be run to align the reads of these split fastqs to the human genome
- **3_process_sample.sh** - For each sample, a job will be run to do the following
    - Combine the aligned BAMs
    - Base quality score recalibration and Mark duplicates of the combined BAM
    - Analyze CNV with CONSERTING
    - Compute QC metrics
        - WGS (or HS metrics), alignment, insert size, base distribution, quality, GC bias, oxidation by GATK
        - WGS (and Exome) and 5 million read downsampled coverage by Bedtools
        - Alignment metrics by QualiMap
        - Estimated future coverage by PreSeq
        - Extracted read counts if barcode or UMI specified
- QC metrics will be summarized
    - Read counts, alignment metrics, oxidative artifacts, duplicates, coverages, preseq, extracted read counts if barcode or UMI specified
    - Initial library concentration correction calculated and plotted
- **summarize_metrics.sh** - A single job will be submitted to summarize sample metrics