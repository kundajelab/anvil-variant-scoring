version 1.0

task run_scoring {
	input {
		File variant_list
		File genome
		File model
		String output_prefix
		File chrom_sizes
		File peaks
		Int n_shufs
		String schema
		Boolean no_hdf5
		String gpu_type
		Int memory_gb
	}

	command <<<
		echo 'Running variant scoring...'

		check_input_file() {
			input_file="$1"
			if [ ! -f "${input_file}" ]; then
				echo "ERROR: Input file ${input_file} does not exist. You need to transfer it."
				echo "MISSING:${input_file}"
				exit 1
			elif [ ! -s "${input_file}" ]; then
				echo "ERROR: Input file ${input_file} is empty. You need to transfer it."
				echo "MISSING:${input_file}"
				exit 1
			else
				if [[ ${input_file} != *.gz ]]; then
					echo "------ The total size is:"
					du -h "${input_file}"
				fi
			fi
		}

		check_input_file ~{variant_list}
		check_input_file ~{genome}
		check input_file ~{model}
		check_input_file ~{chrom_sizes}
		check_input_file ~{peaks}

		output_dir="/cromwell_root$(dirname ~{output_prefix})"
		mkdir -p $output_dir
		new_output_prefix="/cromwell_root~{output_prefix}"
		main() {
			output_file=$(mktemp)
			trap 'rm -f "$output_file"' EXIT
			if [[ ~{no_hdf5} -eq true ]]; then
				python -u /scratch/variant-scorer-ivyraine/src/variant_scoring.per_chrom.py \
					-l ~{variant_list} \
					-g ~{genome} \
					-s ~{chrom_sizes} \
					-m ~{model} \
					-p ~{peaks} \
					-o ${new_output_prefix} \
					-t ~{n_shufs} \
					-sc ~{schema} \
					--no_hdf5 \
					| while IFS= read -r line; do
					printf '%s %s\n' "$(TZ='America/Los_Angeles' date '+%Y-%m-%d %H:%M:%S')" "$line"
					done | tee "$output_file"
			else
				python -u /scratch/variant-scorer-ivyraine/src/variant_scoring.per_chrom.py \
					-l ~{variant_list} \
					-g ~{genome} \
					-s ~{chrom_sizes} \
					-m ~{model} \
					-p ~{peaks} \
					-o ${new_output_prefix} \
					-t ~{n_shufs} \
					-sc ~{schema} \
					| while IFS= read -r line; do
					printf '%s %s\n' "$(TZ='America/Los_Angeles' date '+%Y-%m-%d %H:%M:%S')" "$line"
					done | tee "$output_file"
			fi
			exit_code=${PIPESTATUS[0]}
			output=$(<"$output_file")
			# Here's the exit code
			echo "Exit code: $exit_code"
			# Print output to kubernetes log.
			echo "$output"
			# If the exit code is not 0, then the job failed.
			if [ "$(echo "$output" | grep -i "error" | wc -l)" -gt 1 ] || [ "$exit_code" -ne 0 ]; then
				echo "ERROR: variant_scoring.per_chrom.py failed with exit code $exit_code"
				rm "${new_output_prefix}.variant_scores.tsv"
				exit $exit_code
			fi
		}
		main
		# mkdir "/cromwell_root/test_mkdir"
		# touch "/cromwell_root/test_mkdir/test_touch"
		# File output_score_file = "/cromwell_root/test_mkdir/test_touch"

		echo "Completed!"
		exit 0
	>>>
	output {
		File output_score_file = "/cromwell_root" + output_prefix + ".variant_scores.tsv"
	}
	runtime {
		bootDiskSizeGb: 50
		disks: "local-disk 100 HDD"
		docker: "kundajelab/variant-scorer"
		memory: "~{memory_gb}GB"
		gpuType: "~{gpu_type}"
		gpuCount: 1
		nvidiaDriverVersion: "418.87.00"
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
		Int n_shufs
		String schema
		Boolean no_hdf5
		String gpu_type
		Int memory_gb
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
			no_hdf5 = no_hdf5,
			gpu_type = gpu_type,
			memory_gb = memory_gb
	}
	output {
		File output_score_file = run_scoring.output_score_file
	}
}