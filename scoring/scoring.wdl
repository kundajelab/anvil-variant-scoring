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
	}

	command {
		echo 'Running variant scorer'
		echo "variant_list: ${variant_list}"
		exit 0
	}
	output {
		File result_score_file = output_prefix + ".variant_scores.tsv"
	}
	runtime {
		docker: "kundajelab/variant-scorer"
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
		Int n_shufs
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
		File output_file = run_scoring.result_score_file
	}
}