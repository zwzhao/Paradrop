#!/bin/bash 

#used to differentiate our output from other. Other output is still shown 
# in the case of errors
COLOR='\033[01;33m' 

#Show help if no args passed
if [ $# -lt 1 ]
then
    echo -e "${COLOR}Paradrop build tools." && tput sgr0
    echo -e "This tool installs all needed dependencies in a local virtual environment and can set up Snappy development\n"

    echo -e "To get paradrop on a snappy instance as quickly as possible, run build and install\n"

    echo "Usage:"
    echo -e "  build\t\t build and package dependencies, install paradrop locally"
    # echo -e "  clean\n\t remove virtual environment, clean packages"
    echo -e "  run\t\t run paradrop locally"
    echo -e "  install \t compile snap and install on local snappy virtual machine."
    echo -e "  setup\t\t prepares environment for local snappy testing"
    echo -e "  up\t\t starts a local snappy virtual machine"
    echo -e "  down\t\t closes a local snappy virtual machine"
    echo -e "  connect\t connects to a local snappy virtual machine"

    echo -e "\nDevelopment operations"
    echo -e "  docs\t\t rebuilds sphinx docs for readthedocs"
    echo -e "  update-tools\t uploads build tools to pypi. Requires authentication."
    exit
fi


###
# Utils
###
killvm() {
    if [ -f pid.txt ]; then
        echo -e "${COLOR}Killing snappy virtual machine" && tput sgr0
        KVM="$(cat pid.txt)"
        kill "${KVM}"
        rm pid.txt
    else
        echo -e "${COLOR}Snappy virtual machine is not running" && tput sgr0
    fi
}

build_dnsmasq() {
    test -d third-party || mkdir third-party
    test -d third-party/dnsmasq || git clone git://thekelleys.org.uk/dnsmasq.git third-party/dnsmasq
    pushd third-party/dnsmasq
    LDFLAGS=-static make
    popd
    cp third-party/dnsmasq/src/dnsmasq snap/bin/
}

###
# Operations
###

#  ommented lines are from the older virtualenv way of packaging the app. This seems cleaner
build() {
    echo "Cleaning build directories"

    rm -rf buildenv
    rm -rf paradrop/paradrop.egg-info
    rm -rf paradrop/build
    rm snap/bin/pd

    mkdir buildenv

    echo -e "${COLOR}Loading and building python dependencies"
    # echo -e "${COLOR}Bootstrapping environment" && tput sgr0

    # ./venv.pex buildenv/env
    # source buildenv/env/bin/activate

    echo -e "${COLOR}Installing paradrop" && tput sgr0

    if ! type "pex" > /dev/null; then
        echo 'Please install pex. Try:'
        echo "pip install pex"
        exit
    fi

    # pip install pex
    # pip install -e ./paradrop

    #also-- we can get away without saving the requirements just fine, but readthedocs needs them
    # pip freeze | grep -v 'pex' | grep -v 'paradrop' > docs/requirements.txt
    # pex -r docs/requirements.txt -o snap/bin/pd.pex -m paradrop.main:main -f buildenv/dist

    # pip and bdist doesn't play well together. Turn off the virtualenv.
    # deactivate 

    #the above is somewhat redundant now, but meh
    cd paradrop
    python setup.py bdist_egg -d ../buildenv
    cd ..

    echo -e "${COLOR}Building paradrop-snappy..." && tput sgr0
    
    #Unexpected, but it doesn't like trying to overrite the existing pex
    if [ -f snap/bin/pd ]; then
        rm snap/bin/pd
    fi

    pex --disable-cache paradrop -o snap/bin/pd -m paradrop:main -f buildenv/
    rm -rf *.egg-info

    build_dnsmasq
}

# Generates docs 
docs() {
    virtualenv buildenv/env
    source buildenv/env/bin/activate

    pip install -e ./paradrop
    pip freeze | grep -v 'pex' | grep -v 'paradrop' > docs/requirements.txt
}

clean() {
    echo "Cleaning build directories"

    rm -rf buildenv
    rm -rf paradrop/paradrop.egg-info
    rm snap/bin/pd
}

run() {
    echo -e "${COLOR}Starting Paradrop" && tput sgr0

    if [ ! -f snap/bin/pd ]; then
        echo "Dependency pex not found! Have you built the dependencies yet?"
        echo -e "\t$ $0 build"
        exit
    fi

    snap/bin/pd
}

install() {
    if [ ! -f snap/bin/pd ]; then
        echo "Dependency pex not found! Have you built the dependencies yet?"
        echo -e "\t$ $0 build"
        exit
    fi

    #assuming all snappy dev tools are installed if this one is (snappy-remote, for example)
    if ! type "snappy" > /dev/null; then
        echo 'Snappy development tools not installed. Try:'
        echo "$0 setup"
        exit
    fi

    echo -e "${COLOR}Building snap" && tput sgr0
    
    #build the snap using snappy dev tools and extract the name of the snap
    snappy build snap
    SNAP=$(ls | grep ".snap")

    echo -e "${COLOR}Installing snap" && tput sgr0
    snappy-remote --url=ssh://localhost:8022 install "${SNAP}"
    rm *.snap
    
    exit
}

# Perhaps overkill, but preps the local environment for snappy testing
setup() {
    if ! type "kvm" > /dev/null; then
        echo -e '${COLOR}Installing kvm' && tput sgr0
        sudo apt-get install qemu-kvm -y
    fi

    #check for image only download if it does not already exist
    if [ ! -f snappy-vm.img ]; then
        echo -e "${COLOR}Downloading Snappy image." && tput sgr0

        if ! [ -d "./buildenv" ]; then
            mkdir buildenv
        fi

        wget http://releases.ubuntu.com/15.04/ubuntu-15.04-snappy-amd64-generic.img.xz 
        unxz ubuntu-15.04-snappy-amd64-generic.img.xz
        mv ubuntu-15.04-snappy-amd64-generic.img snappy-vm.img
        rm -rf releases.ubuntu.com
    fi

    if ! type "snappy" > /dev/null; then
        echo -e "${COLOR} Installing snappy tools" && tput sgr0
        sudo add-apt-repository ppa:snappy-dev/tools
        sudo apt-get update
        sudo apt-get install snappy-tools bzr
    fi

    echo -e "${COLOR}Snappy development tools installed" && tput sgr0
}

up() {
    if [ -f pid.txt ]; then
        echo "Snappy virtual machine is already running. If you believe this to be an error, try:"
        echo -e "$0 down"
        exit
    fi

    if [ ! -f snappy-vm.img ]; then
        echo "Snappy image not found. Try:"
        echo -e "\t$0 setup"
        exit
    fi

    echo "Starting snappy instance on local ssh port 8022."
    echo "Please wait for the virtual machine to load."
    kvm -m 512 -netdev user,id=net0,hostfwd=tcp::8090-:80,hostfwd=tcp::8022-:22,hostfwd=tcp::7777-:9000,hostfwd=tcp::9999-:14321 \
            -netdev user,id=net1 -device e1000,netdev=net0 -device e1000,netdev=net1 snappy-vm.img &
    echo $! > pid.txt
}

down() {
    killvm
}

connect() {
    if [ ! -f pid.txt ]; then
        echo "No Snappy virtual machine running. Try:"
        echo -e "$0 up"
        exit
    fi

    echo -e "${COLOR} Connecting to virtual machine. user: ubuntu password: ubuntu" && tput sgr0
    ssh -p 8022 ubuntu@localhost
}


update-tools() {
    cd pdtools
    rm -rf build/
    rm -rf dist/

    python setup.py sdist bdist_wheel
    twine upload dist/* 

    sudo pip install paradrop --upgrade
}

###
# Call Operations
###

case "$1" in
    "build") build;;
    # "clean") clean;;
    "run") run;;
    "install") install;;
    "setup") setup;;
    "up") up;;
    "down") down;;
    "connect") connect;;
    "docs") docs;;
    "update-tools") update-tools;;
    *) echo "Unknown input $1"
   ;;
esac
