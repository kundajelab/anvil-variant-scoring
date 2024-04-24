version 1.0

task hello {

  command {
    echo 'Hello world!'
  }

  output {
    File response = stdout()
  }

  runtime {
   docker: 'ubuntu:impish-20220105'
  }
}

workflow test {
  call hello
  output {
	File response = hello.response
  }
}