#!/usr/bin/sh

set -e

LIBTOOL="/usr/bin/libtool --silent"

INSTALL=/usr/bin/install

scorep_preload_name="scorep_preload"

scorep_preload_dir=".scorep_preload"

print_help()
{
    cat <<EOH
Usage
=====
1. Build the Score-P preload:
> $0 build /path/to/application <scorep-options>

2. Get the preload for the Score-P libraries
> $0 print /path/to/application

You can run your MPI application like this
> LD_PRELOAD=\$($0 print /path/to/application) mpirun -np 4 helloworld

Please, be careful when you use a job scheduler like SLURM or PBS
because they have specific options/variables to set the LD_PRELOAD!

*.Cleaning the workspace
> rm -rf /path/to/application/.scorep_preload
EOH
}

build()
{
	if [ $# -lt 3 ];then
           	echo "Wrong number of arguments"
	  	print_help
		exit -1
        fi

	scorep_preload_dir=$(realpath $2/$scorep_preload_dir)

	if [ -d "$scorep_preload_dir" ]; then
	    	echo "Preload folder already exists!"
	    	echo "For re-building, delete the $scorep_preload_dir folder"
		exit -1
	fi

	mkdir -p "$scorep_preload_dir"

	scorep_init_options="${@:3}"
        
	echo "$scorep_init_options" > "$scorep_preload_dir/scorep_init_options.conf"

	scorep_tmp="$(mktemp -d -t scorep_preload.XXXXXXXXXX)"

	scorep-config $scorep_init_options --adapter-init > "$scorep_tmp/$scorep_preload_name.c"

        ${LIBTOOL} --mode=compile --tag=CC \
		${CC} \
		-c \
		-shared \
		-o "$scorep_tmp/$scorep_preload_name.lo" \
		"$scorep_tmp/$scorep_preload_name.c"

	${LIBTOOL} --mode=link --tag=CC \
		${CC} \
		-aviod-version \
		-module \
		-shared \
		-o "$scorep_tmp/$scorep_preload_name.la" \
		"$(scorep-config $scorep_init_options --ldflags)" \
		"$scorep_tmp/$scorep_preload_name.lo" \
		-rpath "$scorep_preload_dir"

	${LIBTOOL} --mode=install \
		$INSTALL "$scorep_tmp/$scorep_preload_name.la" \
		"$scorep_preload_dir/$scorep_preload_name.la"

	echo "Build Score-P preload in $scorep_preload_dir"

	echo "You can set the preload like this:"
	echo "LD_PRELOAD=\$\($0 print /path/to/application)"

	rm -rf "$scorep_tmp"
}

print_preload()
{
	if [ $# -lt 2 ]; then
		echo "Wrong number of arguments."
		print_help
		exit -1
	fi

	scorep_preload_dir=$(realpath $2/$scorep_preload_dir)

	if [ ! -d "$scorep_preload_dir" ] || [ ! -f "$scorep_preload_dir/scorep_init_options.conf" ]; then
		echo "No Score-P preload folder found in $2"
	        print_help
		exit -1
	fi

	scorep_init_options=$(cat $scorep_preload_dir/scorep_init_options.conf)
	preload_str="$scorep_preload_dir/$scorep_preload_name.so"
	scorep_subsystems=$(scorep-config $scorep_init_options --libs | tr ' ' '\n' | grep -o "scorep.*")
	for i in $scorep_subsystems
	do
		preload_str="$preload_str:$SCOREP_DIR/lib/lib$i.so"
	done
	echo "$preload_str"
}

command -v scorep-config >/dev/null 2>&1 || \
	 { echo "SCORE-P has to be installed on your system. Aborting..."; exit 1; }

export SCOREP_DIR=$(realpath "$(dirname $(which scorep-config))/../")
export CC=$(scorep-config --cc)

if [ "$1" == "build" ]; then
    build "$@"
elif [ "$1" == "print" ]; then
    print_preload "$@"
elif [ "$1" == "help" ]; then
    print_help
fi
