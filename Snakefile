

input_data = "vir_SAMPLEIDs.txt"

samples= [x.strip().split(".tar")[0] for x in open(input_data, 'r')]

k_sizes= ["21","31","51"]

  #takes first 5 sample
samples=samples[:5]

#print(samples)

rule all:
    input: 
        # uncompress_genome
        #expand("raw_data/zipped_data/{sample}_{ext}.bz2", sample =samples, ext = [1,2])
        #expand("raw_data/zipped_data/{sample}_1_sequence.txt.bz2", sample =samples),
        #expand("raw_data/zipped_data/{sample}_2_sequence.txt.bz2", sample =samples),
        #expand("fastp/{sample}_1.trimmed.gz", sample=samples),
        #expand("fastp/{sample}_2.trimmed.gz", sample=samples),
        #expand("sourmash/sig/{sample}.sig", sample=samples),
        #expand("sourmash/compare/virHMP_compare_k{ksize}_unfiltered.csv", ksize=k_sizes),
        #expand("sourmash/gather/{sample}_gather.csv",sample=samples)
        #expand("kmer/{sample}.kmertrim.fq.gz", sample=samples)
        #expand("sourmash/plots/virHMP_compare_k{ksize}_unfiltered.numpy.dendro.pdf", ksize=k_sizes),
        #expand("sourmash/plots/virHMP_compare_k{ksize}_unfiltered.numpy.hist.pdf", ksize=k_sizes),
        #expand("sourmash/plots/virHMP_compare_k{ksize}_unfiltered.numpy.matrix.pdf", ksize=k_sizes)
        expand("sourmash/gather/{sample}_gather.csv", sample = samples)

rule download_data:
    output: "raw_data/zipped_data/{sample}.tar"
    params: URL= lambda wildcards: "https://ibdmdb.org/tunnel/static/HMP2/Viromics/1732/" + wildcards.sample + ".tar"
    shell: "wget -O {output} {params.URL}"


rule uncompress_genome:
    input: "raw_data/zipped_data/{sample}.tar"
    output: 
        "raw_data/zipped_data/{sample}_1_sequence.txt.bz2",
        "raw_data/zipped_data/{sample}_2_sequence.txt.bz2" 
    shell:
        "tar xvf {input} -C raw_data/zipped_data/"
rule bzip_to_gzip:
    input: 
        F1="raw_data/zipped_data/{sample}_1_sequence.txt.bz2",
        F2="raw_data/zipped_data/{sample}_2_sequence.txt.bz2"
    output:
        F1="raw_data/zipped_data/{sample}_1.gz", 
        F2="raw_data/zipped_data/{sample}_2.gz"
    log:
        "logs/gzip/{sample}_gzip.log"  
    benchmark:
        "logs/gzip/{sample}_gzip.benchmark"  
    resources:
        # minutes to allocate for sbatch in slurm
        runtime = 20,
        # memory to allocate in mb
        mem_mb = 1000
    threads: 1
    shell:
        """
        bzcat {input.F1} | gzip -c -9 > {output.F1} 2> {log}
        bzcat {input.F2} | gzip -c -9 > {output.F2} 2>> {log}
        """

rule fastp:
    input:
        R1="raw_data/zipped_data/{sample}_1.gz", 
        R2="raw_data/zipped_data/{sample}_2.gz"
    output:
        R1="fastp/{sample}_1.trimmed.gz", 
        R2="fastp/{sample}_2.trimmed.gz",
        html="fastp/{sample}_fastp.html",
        json="fastp/{sample}_fastp.json"
    log:
        "logs/fastp/{sample}_fastp.log"  
    benchmark:
        "logs/fastp/{sample}_fastp.benchmark"  
    conda:
        "virHMP_env.yml"
    shell:
        """
        fastp -i {input.R1} -I {input.R2}  \
        -o {output.R1} -O {output.R2} \
        -h {output.html} -j {output.json} > {log}
        """

rule remove_host:
    input:
        R1 = "fastp/{sample}_1.trim.fastq.gz",
        R2 = "fastp/{sample}_2.trim.fastq.gz",
        human = "databases/hg19_main_mask_ribo_animal_allplant_allfungus.fa.gz"
    output:
        R1 = "bbduk/{sample}_1.nohost.fq.gz",
        R2 = "bbduk/{sample}_2.nohost.fq.gz",
        human_R1 = "bbduk/{sample}_1.human.fq.gz",
        human_R2 = "bbduk/{sample}_2.human.fq.gz"
    #bbduk requires 64gb of mem, and requires "-n 4" in srun command
    shell:
        """
        bbduk.sh -Xmx64g t=4 in={input.R1} in2={input.R2} out={output.R1} out2={output.R2} outm={output.human_R1} outm2={output.human_R2} k=31 ref={input.human}
        """


rule khmer: 
    input:
        R1="fastp/{sample}_1.trimmed.gz",
        R2="fastp/{sample}_2.trimmed.gz"
    output:"kmer/{sample}.kmertrim.fq.gz"
    shell:
        """
        interleave-reads.py {input.R1} {input.R2} | \
        trim-low-abund.py --gzip -C 3 -Z 18 -M 20e9 -V - -o {output}
        """


#### Sourmashy Stuff ####

rule sourmash_compute:
    input: "kmer/{sample}.kmertrim.fq.gz"
    output:
        "sourmash/sig/{sample}.sig"
    params:
        ksizes=",".join(k_sizes)
    log:
        "logs/sourmash/sig/{sample}_sig.log"
    benchmark:
        "logs/sourmash/sig/{sample}_sig.benchmark"
    conda:
        "virHMP_env.yml"
    shell:"""
        sourmash compute -k {params.ksizes} --scaled 500 --merge {wildcards.sample} --track-abundance -o {output} {input}
    """

rule sourmash_compare:
    input: expand("sourmash/sig/{sample}.sig", sample=samples)
    output:
        csv="sourmash/compare/virHMP_compare_k{ksize}_unfiltered.csv",
        numpy="sourmash/compare/virHMP_compare_k{ksize}_unfiltered.numpy"
        
    shell:"""
        sourmash compare {input} -k {wildcards.ksize} -o {output.numpy} --csv {output.csv}
    """

### add a sm plot rule, takes numpy output of ^ and makes a heatmap (pdf) ( sourmash plot --help)

rule sourmash_plot:
#    input: expand("sourmash/compare/virHMP_compare_k{ksize}_unfiltered.numpy", ksize=k_sizes)
    input: "sourmash/compare/virHMP_compare_k{ksize}_unfiltered.numpy"
    output:
        "sourmash/plots/virHMP_compare_k{ksize}_unfiltered.numpy.dendro.pdf",
        "sourmash/plots/virHMP_compare_k{ksize}_unfiltered.numpy.hist.pdf",
        "sourmash/plots/virHMP_compare_k{ksize}_unfiltered.numpy.matrix.pdf"

    shell:"""
        sourmash plot --pdf --labels {input} --output sourmash/plots/
    """

rule download_gather_genbank:
    output: "gather_databases/genbank-k31.sbt.zip"
    params:
        dl_link="https://osf.io/jgu93/download"
    shell:
        """
        wget -O {output} {params.dl_link}
        """

rule sourmash_gather:
    input:
        query="sourmash/sig/{sample}.sig",
        database="gather_databases/genbank-k31.sbt.zip"
    output:
        csv="sourmash/gather/{sample}_gather.csv",
        matches="{sample}_gather_matched.sig",
        
        #unassigned is the one likely to only have viral sigs
        unassigned="{sample}_gather_unassigned.sig",
        report="sourmash/gather/{sample}_report.txt"
    log:
        "logs/sourmash/gather/{sample}_gather.log"
    benchmark:
        "logs/sourmash/gather/{sample}_gather.benchmark"
    conda:
        "virHMP_env.yml"
    shell:
        """
        sourmash gather {input.query} {input.database} -k 31 --threshold-bp=0 --scaled 2000 --save-matches {output.matches} --output-unassigned {output.unassigned} -o {output.csv} >& {output.report} 2> {log}
        """
