# Guide to WGS_WES_Pipeline

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
- Optional arguments: -b/--run_dir >arg<, -s/--sample_sheet >arg<, --R1_suffix >arg<, --R2_suffix >arg<, -o/--err_out_dir >arg<, --b37, --novaseq_wgs, --dup_mark_again, --skip_dup_mark, --remove_dups, --dup_pixel_distance >arg<, --no_variant_class, --bam_suffix >arg<, --slurm
    - If you want to have the script demultiplx your BCL files into fastq.gz files, add the option *-b* or *--run_dir* followed by the full path to your directory with the BCL files. The program will look for a sample sheet called SampleSheet.csv in the first level within the run_dir or you can specify a different sample sheet by adding the option *--sample_sheet* followed by the full path to that file. The program will make the fastq directory if it does not exist and tell you the sizes of undeteremined vs fully demultiplexed reads
    - If your read 1 and read 2 fastq.gz files differentiate themselves by some pattern other than _L001_R1_001.fastq.gz and _L001_R2_001.fastq.gz or _R1_001.fastq.gz and _R2_001.fastq.gz, add the option *--R1_suffix* followed by the R1 suffix and add the option *--R2_suffix* followed by the R2 suffix
    - If you want to specify a different directory to output the standard error and out print statements of all jobs, add the option *--err_out_dir* followed by your preferred directory
    - If you want to switch the reference genome version to the hg19 subtype b37, add the option *--b37*
    - If you are running a Novaseq WGS run, add the option *--novaseq_wgs* to increase the memory allotted to certain jobs to ensure they run without errors
    - If the pipeline failed because MarkDuplicates ran out of memory, run again and add the option *--dup_mark_again*
    - If you want to skip duplicate marking, add the option *--skip_dup_mark*
    - If you want to remove duplicates instead of just marking them, add the option *--remove_dups*
    - If you want to analyze data from a patterned flow cell (e.g. NovaSeq, HiSeq) instead of an unpattered flow cell (e.g. NextSeq, MiniSeq) then it's recommended to change the optical duplicate pixel distance from the default of 100 to 2500 by adding the option *--dup_pixel_distance* followed by 2500 or your preferred optical duplicate pixel distance
    - If you want to skip the slow summing of variant classes that gets performed by default using samtools pileup and bcftools then add the option *--no_variant_class*
    - If your BAMs do not end in ".bqsr.marked.bam" then specify their suffix with the option *--bam_suffix* followed by your BAM suffix
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