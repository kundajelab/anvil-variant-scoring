version 1.0

task run_scoring {
	input {
		File variant_list
		File genome
		File model
		String output_prefix
		File chrom_sizes
		File peaks
		File n_shufs
		String schema
		Boolean no_hdf5
	}

	command {
		nl -ba -n ln -w3 -s' ' /scratch/variant-scorer-ivyraine/src/variant_scoring.per_chrom.py

		mkdir -p /mnt/volume/variant_scoring/ENCSR999NKW/fold_0/

		echo "Starting pipeline..."
		main() {

		# This is to capture the output of the command, and also print it as it runs
		output_file=$(mktemp)
		trap 'rm -f "$output_file"' EXIT

		python -u /scratch/variant-scorer-ivyraine/src/variant_scoring.per_chrom.py \
			-l /mnt/volume/oak/stanford/groups/akundaje/projects/encode_variant_scoring/snp_lists/encode_variants.tsv \
			-g /mnt/volume/oak/stanford/groups/akundaje/soumyak/refs/hg38/GRCh38_no_alt_analysis_set_GCA_000001405.15.fasta \
			-s /mnt/volume/oak/stanford/groups/akundaje/soumyak/refs/hg38/GRCh38_EBV.chrom.sizes.tsv \
			-m /mnt/volume/oak/stanford/groups/akundaje/projects/chromatin-atlas-2022/ATAC/ENCSR999NKW/chrombpnet_model_feb15/chrombpnet_wo_bias.h5 \
			-p /mnt/volume/oak/stanford/groups/akundaje/projects/chromatin-atlas-2022/ATAC/ENCSR999NKW/preprocessing/downloads/peaks.bed.gz \
			-o /mnt/volume/variant_scoring/ENCSR999NKW/fold_0/ \
			-t 1000000 \
			-sc chrombpnet \
			--no_hdf5 \
			| while IFS= read -r line; do
			printf '%s %s\n' "$(TZ='America/Los_Angeles' date '+%Y-%m-%d %H:%M:%S')" "$line"
			done | tee "$output_file"

		exit_code=${PIPESTATUS[0]}
		output=$(<"$output_file")

		# Here's the exit code
		echo "Exit code: $exit_code"
		
		# Print output to kubernetes log.
		echo "$output"

		# If the exit code is not 0, then the job failed.
		if [ "$(echo "$output" | grep -i "error" | wc -l)" -gt 1 ] || [ "$exit_code" -ne 0 ]; then
		# if [ "$(echo "$output" | grep -i "error" | wc -l)" -gt 1 ]; then
		# if [ "$exit_code" -ne 0 ]; then
			echo "ERROR: chrombpnet bias pipeline failed with exit code $exit_code"
			exit $exit_code
		fi
		}

		main

		echo "Completed!"
	}
	output {
		result_score_file = output_prefix + ".variant_scores.tsv"
	}
	runtime {
		docker: 'kundajelab/variant-scorer'
		memory: 64 + "GB"
		bootDiskSizeGb: 50
		disks: "local-disk 100 HDD"
		maxRetries: 1
	}
}


workflow scoring {
	input {
		File variant_list
		File genome
		File model
		String output_prefix
		File chrom_sizes
		File peaks
		File n_shufs
		String schema
		Boolean no_hdf5
	}
	call run_scoring {
		input: 
			variant_list = variant_list,
			genome = genome,
			model = model,
			output_prefix = output_prefix,
			chrom_sizes = chrom_sizes,
			peaks = peaks,
			n_shufs = n_shufs,
			schema = schema,
			no_hdf5 = no_hdf5
	}
	output {
		File output_file = run_scoring.output_file
	}
}