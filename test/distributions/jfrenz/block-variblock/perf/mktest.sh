#!/bin/bash

NAME=$1
NUMLOCS=$2

isNumRe='^[0-9]+$'

if [ -z $NAME ] ; then
    echo "Test name not supplied"
    exit 1
fi

if [ -z $NUMLOCS ] ; then
    echo "Number of locales not supplied"
    exit 1
fi

if [ -d $NAME ] ; then
    echo "Directory called ${NAME} exists"
    exit 1
fi

if [ -f $NAME ] ; then
    echo "File called ${NAME} exists"
    exit 1
fi


if ! [[ $NUMLOCS =~ $isNumRe ]] ; then
    echo "Supplied number of locales isn't a number: ${NUMLOCS}"
    exit 1
fi

if [ 2 -gt $NUMLOCS ] ; then
    echo "Number of locales must be 2 or greter"
    exit 1
fi

echo "Creating test called ${NAME} for ${NUMLOCS} locales..."

mkdir $NAME
pushd $NAME

# Create perfkeys for comms
for dist in Block VB_Even VB_StaticCut ; do
    for((loc = 0; loc < $NUMLOCS; loc++)); do
        for stat in get get_nb put put_nb test_nb wait_nb try_nb fork fork_fast fork_nb ; do
            echo "${dist}-COMMS-INIT-LOCALE${loc}-${stat}:" >> ${NAME}-${dist}-Comms.perfkeys
            echo "${dist}-COMMS-RUN-LOCALE${loc}-${stat}:" >> ${NAME}-${dist}-Comms.perfkeys
        done
    done
    echo "verify:-4:Distribution: ${dist}" >>  ${NAME}-${dist}-Comms.perfkeys
    echo "verify:-3:Test: Comms" >>  ${NAME}-${dist}-Comms.perfkeys
    echo "verify:-2:Validation: SUCCESS" >>  ${NAME}-${dist}-Comms.perfkeys
done

# Create perfkeys for memory
for dist in Block VB_Even VB_StaticCut ; do
    for((loc = 0; loc < $NUMLOCS; loc++)); do
        for stat in BEGIN PRERUN POSTRUN ; do
            echo "${dist}-MEM-${stat}-LOCALE${loc}:" >> ${NAME}-${dist}-Mem.perfkeys
        done
    done
    echo "verify:-4:Distribution: ${dist}" >>  ${NAME}-${dist}-Mem.perfkeys
    echo "verify:-3:Test: Mem" >>  ${NAME}-${dist}-Mem.perfkeys
    echo "verify:-2:Validation: SUCCESS" >>  ${NAME}-${dist}-Mem.perfkeys
done

# Create perfkeys for time
for dist in Block VB_Even VB_StaticCut ; do
    echo "${dist}-TIME-INIT:" >>  ${NAME}-${dist}-Time.perfkeys
    echo "${dist}-TIME-RUN:" >>  ${NAME}-${dist}-Time.perfkeys
    echo "verify:-4:Distribution: ${dist}" >>  ${NAME}-${dist}-Time.perfkeys
    echo "verify:-3:Test: Time" >>  ${NAME}-${dist}-Time.perfkeys
    echo "verify:-2:Validation: SUCCESS" >>  ${NAME}-${dist}-Time.perfkeys
done


# Create perfcompopts file
cat <<EOT >> ${NAME}.perfcompopts
-M ../common/ --dynamic --ignore-local-classes
EOT

# Create perfexecopts file
cat <<EOT >> ${NAME}.perfexecopts
--distType=Block            --testType=Comms                    # ${NAME}-Block-Comms.perfkeys
--distType=Block            --testType=Mem      --memTrack      # ${NAME}-Block-Mem.perfkeys
--distType=Block            --testType=Time                     # ${NAME}-Block-Time.perfkeys
--distType=VB_Even          --testType=Comms                    # ${NAME}-VB_Even-Comms.perfkeys
--distType=VB_Even          --testType=Mem      --memTrack      # ${NAME}-VB_Even-Mem.perfkeys
--distType=VB_Even          --testType=Time                     # ${NAME}-VB_Even-Time.perfkeys
--distType=VB_StaticCut     --testType=Comms                    # ${NAME}-VB_StaticCut-Comms.perfkeys
--distType=VB_StaticCut     --testType=Mem      --memTrack      # ${NAME}-VB_StaticCut-Mem.perfkeys
--distType=VB_StaticCut     --testType=Time                     # ${NAME}-VB_StaticCut-Time.perfkeys
EOT

# Create a numlocales file
echo "${NUMLOCS}" > NUMLOCALES

# Create a base chpl file
cat <<EOT >> ${NAME}.chpl
use VbBenchFw;

config const N = 32;
const Space = {1..#N, 1..#N};

class Prog {
    const dist;
    const dom: domain(2) dmapped dist = Space;
    const arr: [dom] real;
    
    proc Prog(dist, correctness: bool) {
        if numLocales != ${NUMLOCS} then {
            halt("Number of locales must be ${NUMLOCS}");
        }
        
        // Do your initialization here
    }
    
    proc run(): bool {
        // Add actual computing loops here
        return true;
    }
    
    proc preRunInfo() {
        // Dump arrays and print other data for example
    }
    
    proc postRunInfo() {
        // Dump arrays and print other data for example
    }
}

class Maker {
    proc this(dist, correctness: bool) {
        return new Prog(dist, correctness: bool);
    }
}

VbBenchRun(new Maker(), Space);
EOT

popd
