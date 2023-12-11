#!/bin/bash -e
# 3dprintyourbrain, adapted script by skjerns, original by miykael
# usage: create_3d_brain.sh subject_name.nii.gz
###############################################

######### settings that you might need to adapt ########
# Path to meshlabserver 
export MESHLAB_SERVER="/mnt/c/Program Files/VCG/MeshLab/meshlabserver.exe"
######### end of settings

set -e -v # exit on error

export FSLOUTPUTTYPE=NIFTI_GZ
# Main folder for the whole project
export subjT1=$1 # the NIFTI file

export MAIN_DIR=$HOME/3dbrains

# Name of the subject
export subject=$(echo "$subjT1" | rev | cut -f 1 -d '/' | rev | cut -f 1 -d '.')

# Path to the subject (output folder)
export SUBJECTS_DIR=$MAIN_DIR/${subject}/output

#==========================================================================================
#2. Create Surface Model with FreeSurfer
#==========================================================================================
mkdir -p $MAIN_DIR/${subject}/
mkdir -p $SUBJECTS_DIR/mri/orig
mri_convert ${subjT1} $SUBJECTS_DIR/mri/orig/001.mgz
recon-all -subjid "output" -all -time -log logfile -nuintensitycor-3T -sd "$MAIN_DIR/${subject}/" -parallel

#==========================================================================================
#3. Create 3D Model of Cortical and Subcortical Areas
#==========================================================================================

# CORTICAL
# Convert output of step (2) to fsl-format
mris_convert --combinesurfs $SUBJECTS_DIR/surf/lh.pial $SUBJECTS_DIR/surf/rh.pial \
             $SUBJECTS_DIR/cortical.stl

# SUBCORTICAL
mkdir -p $SUBJECTS_DIR/subcortical
# First, convert aseg.mgz into NIfTI format
mri_convert $SUBJECTS_DIR/mri/aseg.mgz $SUBJECTS_DIR/subcortical/subcortical.nii

# Second, binarize all areas that you're not interested and inverse the binarization
mri_binarize --i $SUBJECTS_DIR/subcortical/subcortical.nii \
             --match 2 3 24 31 41 42 63 72 77 51 52 13 12 43 50 4 11 26 58 49 10 17 18 53 54 44 5 80 14 15 30 62 \
             --inv \
             --o $SUBJECTS_DIR/subcortical/bin.nii

# Third, multiply the original aseg.mgz file with the binarized files
fslmaths.fsl $SUBJECTS_DIR/subcortical/subcortical.nii \
         -mul $SUBJECTS_DIR/subcortical/bin.nii \
         $SUBJECTS_DIR/subcortical/subcortical.nii.gz

# Fourth, copy original file to create a temporary file
cp $SUBJECTS_DIR/subcortical/subcortical.nii.gz $SUBJECTS_DIR/subcortical/subcortical_tmp.nii.gz

# Fifth, unzip this file
gunzip -f $SUBJECTS_DIR/subcortical/subcortical_tmp.nii.gz

# Sixth, check all areas of interest for wholes and fill them out if necessary
for i in 7 8 16 28 46 47 60 251 252 253 254 255
do
    mri_pretess $SUBJECTS_DIR/subcortical/subcortical_tmp.nii \
    $i \
    $SUBJECTS_DIR/mri/norm.mgz \
    $SUBJECTS_DIR/subcortical/subcortical_tmp.nii
done

# Seventh, binarize the whole volume
fslmaths.fsl $SUBJECTS_DIR/subcortical/subcortical_tmp.nii -bin $SUBJECTS_DIR/subcortical/subcortical_bin.nii

# Eighth, create a surface model of the binarized volume with mri_tessellate
mri_tessellate $SUBJECTS_DIR/subcortical/subcortical_bin.nii.gz 1 $SUBJECTS_DIR/subcortical/subcortical

# Ninth, convert binary surface output into stl format
mris_convert $SUBJECTS_DIR/subcortical/subcortical $SUBJECTS_DIR/subcortical.stl


"$MESHLAB_SERVER" -i $SUBJECTS_DIR/subcortical.stl -o $SUBJECTS_DIR/subcortical.stl -m sa -s smoothing.mlx
"$MESHLAB_SERVER" -i $SUBJECTS_DIR/cortical.stl -o $SUBJECTS_DIR/cortical.stl -m sa -s smoothing.mlx

#==========================================================================================
#4. Combine Cortical and Subcortial 3D Models
#==========================================================================================

echo 'solid '$SUBJECTS_DIR'/final.stl' > $SUBJECTS_DIR/final.stl
sed '/solid vcg/d' $SUBJECTS_DIR/cortical.stl >> $SUBJECTS_DIR/final.stl
sed '/solid vcg/d' $SUBJECTS_DIR/subcortical.stl >> $SUBJECTS_DIR/final.stl
echo 'endsolid '$SUBJECTS_DIR'/final.stl' >> $SUBJECTS_DIR/final.stl

#==========================================================================================
# Cleanup
#==========================================================================================
rm -R -- $SUBJECTS_DIR/*/
rm $SUBJECTS_DIR/logfile

#==========================================================================================
#5. ScaleDependent Laplacian Smoothing, create a smoother surface: MeshLab
#==========================================================================================
"$MESHLAB_SERVER" -i $SUBJECTS_DIR/final.stl -o $SUBJECTS_DIR/final.stl -s close_decimate.mlx
