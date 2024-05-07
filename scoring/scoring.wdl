version 1.0

task run_scoring {
	input {
		File variant_list
		File genome
		File model
		String output_tar
		File chrom_sizes
		File peaks
		Int n_shufs
		String schema
		Boolean no_hdf5
		String gpu_type
		Int memory_gb
	}

	String output_score_file_temp = "output_score_file.temp"
	String missing_files_temp = "missing_files.temp"
	String is_complete_temp = "is_complete.temp"

	command <<<
		echo 'Running variant scoring...'
		set -x
		# Exits with zero if:
		# - All input files exist and are non-empty.
		# - Everything works as expected.
		# Exits with non-zero if:
		# - The script has a logical error.
		# - The existing files don't work with the script.

		# Create intermediate files.
		# touch "~{output_score_file_temp}"
		echo "~{output_tar}" > "~{output_score_file_temp}"
		touch "~{output_tar}" 
		touch "~{missing_files_temp}"
		echo "false" > "~{is_complete_temp}"

		is_missing_files=false
		check_input_file() {
			input_file="$1"
			if [ ! -f "${input_file}" ]; then
				echo "ERROR: Input file ${input_file} does not exist. You need to transfer it."
				echo "${input_file}\n" >> "~{missing_files_temp}"
				is_missing_files=true
			elif [ ! -s "${input_file}" ]; then
				echo "ERROR: Input file ${input_file} is empty. You need to transfer it."
				echo "${input_file}\n" >> "~{missing_files_temp}"
				is_missing_files=true
			else
				if [[ ${input_file} != *.gz ]]; then
					echo "------ The total size is:"
					du -h "${input_file}"
				fi
			fi
		}
		# Exit if missing files.
		if [ "$is_missing_files" = true ]; then
			echo "ERROR: Missing input files:\n$(cat ~{missing_files_temp})\nExiting."
			exit 0
		fi

		check_input_file "~{variant_list}"
		check_input_file "~{genome}"
		check input_file "~{model}"
		check_input_file "~{chrom_sizes}"
		check_input_file "~{peaks}"

		new_output_prefix="$(dirname ~{output_tar})"
		mkdir -p $new_output_prefix
		main() {
			output_file=$(mktemp)
			trap 'rm -f "$output_file"' EXIT
			if [[ ~{no_hdf5} -eq true ]]; then
				python -u /scratch/variant-scorer-ivyraine/src/variant_scoring.per_chrom.py \
					-l "~{variant_list}" \
					-g "~{genome}" \
					-s "~{chrom_sizes}" \
					-m "~{model}" \
					-p "~{peaks}" \
					-o "${new_output_prefix}" \
					-t ~{n_shufs} \
					--forward_only \
					-sc ~{schema} \
					--no_hdf5 \
					| while IFS= read -r line; do
					printf '%s %s\n' "$(TZ='America/Los_Angeles' date '+%Y-%m-%d %H:%M:%S')" "$line"
					done | tee "$output_file"
			else
				python -u /scratch/variant-scorer-ivyraine/src/variant_scoring.per_chrom.py \
					-l "~{variant_list}" \
					-g "~{genome}" \
					-s "~{chrom_sizes}" \
					-m "~{model}" \
					-p "~{peaks}" \
					-o "${new_output_prefix}" \
					-t ~{n_shufs} \
					--forward_only \
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
				exit $exit_code
			fi
		}
		main

		echo "Scoring complete. Now tarring result folder."
		tar -czvf "$(basename ~{output_tar})" -C "$(dirname ~{output_tar})" .; mv "$(basename ~{output_tar})" "~{output_tar}"
		echo "~{output_tar}" > "~{output_score_file_temp}"
		echo "true" > "~{is_complete_temp}"

		echo "Completed!"
		set +x
		exit 0
	>>>
	output {
		File output_score_file = read_string("~{output_score_file_temp}")
		String missing_files = read_string("~{missing_files_temp}")
		Boolean is_complete = read_boolean("~{is_complete_temp}")
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
		String output_tar
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
			output_tar = output_tar,
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
		String missing_files = run_scoring.missing_files
		Boolean is_complete = run_scoring.is_complete
	}
}
