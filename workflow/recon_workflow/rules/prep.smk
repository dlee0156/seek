"""
===============================================
01. Prep Reconstruction Workflow and BIDS Layout
===============================================

In this pipeline, we prep the reconstruction workflow
by putting MRI and CT data into the BIDS layout and
re-orient images to RAS with ACPC alignment.

We assume that there is only one set of dicoms for CT and MRI
data.

This pipeline depends on the following functions:

    * mrconvert
    * acpcdetect

from FreeSurfer6+, acpcdetect2.0. To create a DAG pipeline, run:

    snakemake --dag | dot -Tpdf > dag_pipeline_reconstruction.pdf

"""

# Authors: Adam Li <adam2392@gmail.com>
# License: GNU

import os
import sys
from pathlib import Path
from mne_bids import BIDSPath

# hack to run from this file folder
sys.path.append("../../../")
from seek.pipeline.utils.fileutils import (BidsRoot, BIDS_ROOT, _get_seek_config,
                                           _get_anat_bids_dir, _get_ct_bids_dir,
                                           _get_bids_basename, _get_subject_center)

configfile: _get_seek_config()

# get the actual file path to the config
configpath = Path(_get_seek_config()).parent

# get the freesurfer patient directory
bids_root = BidsRoot(BIDS_ROOT(config['bids_root']),
                     center_id=_get_subject_center(subjects, centers, subject)
                     )
subject_wildcard = "{subject}"

# import pandas as pd

# subjects = pd.read_table(configdir / config["subjects"]).set_index("subject", drop=False)

# initialize directories that we access in this snakemake
FS_DIR = bids_root.freesurfer_dir
RAW_CT_FOLDER = bids_root.get_rawct_dir(subject_wildcard)
RAW_MRI_FOLDER = bids_root.get_premri_dir(subject_wildcard)
FSOUT_MRI_FOLDER = Path(bids_root.get_freesurfer_patient_dir(subject_wildcard)) / "mri"
FSOUT_CT_FOLDER = Path(bids_root.get_freesurfer_patient_dir(subject_wildcard)) / "CT"
FSOUT_ACPC_FOLDER = Path(bids_root.get_freesurfer_patient_dir(subject_wildcard)) / "acpc"

BIDS_PRESURG_ANAT_DIR = _get_anat_bids_dir(bids_root.bids_root, subject_wildcard, session='presurgery')
BIDS_PRESURG_CT_DIR = _get_ct_bids_dir(bids_root.bids_root, subject_wildcard, session='presurgery')

# original native files
ct_native_bids_fname = _get_bids_basename(subject_wildcard,
                                          session='presurgery', space='orig',
                                          imgtype='CT', ext='nii')
premri_native_bids_fname = _get_bids_basename(subject_wildcard,
                                              session='presurgery',
                                              space='orig',
                                              imgtype='T1w', ext='nii')

# robust fov file
premri_robustfov_native_bids_fname = _get_bids_basename(subject_wildcard,
                                                        session='presurgery',
                                                        space='orig',
                                                        processing='robustfov',
                                                        imgtype='T1w', ext='nii')
# after ACPC
premri_bids_fname = _get_bids_basename(subject_wildcard,
                                       session='presurgery',
                                       space='ACPC',
                                       imgtype='T1w', ext='nii')

# COregistration filenames
ctint1_bids_fname = _get_bids_basename(subject_wildcard, session='presurgery',
                                       space='T1w',
                                       imgtype='CT', ext='nii')

from_id = 'CT'  # post implant CT
to_id = 'T1w'  # freesurfer's T1w
kind = 'xfm'
pre_to_post_transform_fname = BIDSPath(subject=subject_wildcard,
                                                 session='presurgery',
                                                 space='T1w').basename + \
                              f"_from-{from_id}_to-{to_id}_mode-image_{kind}.mat"

# after ACPC
ctint1_acpc_bids_fname = _get_bids_basename(subject_wildcard,
                                            session='presurgery',
                                            space='T1wACPC',
                                            imgtype='CT', ext='nii')

from_id = 'CT'  # post implant CT
to_id = 'T1w'  # freesurfer's T1w
kind = 'xfm'
pre_to_post_acpc_transform_fname = BIDSPath(subject=subject_wildcard,
                                                      session='presurgery',
                                                      space='T1wACPC').basename + \
                                   f"_from-{from_id}_to-{to_id}_mode-image_{kind}.mat"

# output files
# raw T1/CT output
ct_output = os.path.join(BIDS_PRESURG_CT_DIR, ct_native_bids_fname)
t1_output = os.path.join(BIDS_PRESURG_ANAT_DIR, premri_bids_fname)

# raw CT to T1 image and map
ct_tot1_output = os.path.join(BIDS_PRESURG_CT_DIR, ctint1_bids_fname)
ct_tot1_map = os.path.join(BIDS_PRESURG_CT_DIR, pre_to_post_transform_fname)

# T1 acpc and CT to T1acpc image and map
t1_acpc_output = os.path.join(BIDS_PRESURG_ANAT_DIR, premri_bids_fname)
ct_tot1_acpc_output = os.path.join(BIDS_PRESURG_CT_DIR, ctint1_acpc_bids_fname)
ct_tot1_acpc_map = os.path.join(BIDS_PRESURG_CT_DIR, pre_to_post_acpc_transform_fname)

print('In prep workflow.')

rule prep:
    input:
         MRI_NIFTI_IMG=expand(t1_output, subject=subjects),
         CT_bids_fname=expand(ct_output, subject=subjects),
         ct_tot1_output=expand(ct_tot1_output, subject=subjects),
         ct_tot1_map=expand(ct_tot1_map, subject=subjects),
         t1_acpc_output=expand(t1_acpc_output, subject=subjects),
         ct_tot1_acpc_output=expand(ct_tot1_acpc_output, subject=subjects),
         ct_tot1_acpc_map=expand(ct_tot1_acpc_map, subject=subjects),
    params:
          bids_root=bids_root.bids_root,
    output:
          report=report('fig1.png', caption='report/figprep.rst', category='Prep')
    shell:
         "echo 'done';"
         "bids-validator {params.bids_root};"
         "touch fig1.png {output};"
"""
Rule for prepping fs_recon by converting dicoms -> NIFTI images.

For more information, see BIDS specification.
"""
rule convert_dicom_to_nifti_mri:
    params:
          MRI_FOLDER=RAW_MRI_FOLDER,
          bids_root=bids_root.bids_root,
    log: "logs/recon_workflow.{subject}.log"
    output:
          MRI_bids_fname=os.path.join(BIDS_PRESURG_ANAT_DIR, premri_native_bids_fname),
    shell:
         "mrconvert {params.MRI_FOLDER} {output.MRI_bids_fname};"

"""
Rule for prepping fs_recon by converting dicoms -> NIFTI images.

For more information, see BIDS specification.
"""
rule convert_dicom_to_nifti_ct:
    params:
          CT_FOLDER=RAW_CT_FOLDER,
          bids_root=bids_root.bids_root,
    log: "logs/recon_workflow.{subject}.log"
    output:
          CT_bids_fname=os.path.join(BIDS_PRESURG_CT_DIR, ct_native_bids_fname),
    shell:
         "mrconvert {params.CT_FOLDER} {output.CT_bids_fname};"

"""
Add comment.
"""
rule t1w_compute_robust_fov:
    input:
         MRI_bids_fname=os.path.join(BIDS_PRESURG_ANAT_DIR, premri_native_bids_fname),
    log: "logs/recon_workflow.{subject}.log"
    output:
          MRI_bids_fname_gz=os.path.join(FSOUT_ACPC_FOLDER, premri_robustfov_native_bids_fname) + '.gz',
          MRI_bids_fname=os.path.join(BIDS_PRESURG_ANAT_DIR, premri_robustfov_native_bids_fname),
    container:
             "docker://neuroseek/seek",
    shell:
         "echo 'robustfov -i {input.MRI_bids_fname} -r {output.MRI_bids_fname_gz}';"
         'robustfov -i {input.MRI_bids_fname} -r {output.MRI_bids_fname_gz};'  # -m roi2full.mat
         'mrconvert {output.MRI_bids_fname_gz} {output.MRI_bids_fname} --datatype uint16;'

"""
Rule for automatic ACPC alignment using acpcdetect software. 

Please check the output images to quality assure that the ACPC was properly
aligned.  
"""
rule t1w_automatic_acpc_alignment:
    input:
         MRI_bids_fname=os.path.join(BIDS_PRESURG_ANAT_DIR, premri_robustfov_native_bids_fname),
    log: "logs/recon_workflow.{subject}.log"
    params:
          anat_dir=str(BIDS_PRESURG_ANAT_DIR),
          acpc_fs_dir=str(FSOUT_ACPC_FOLDER),
    output:
          MRI_bids_fname_fscopy=os.path.join(FSOUT_ACPC_FOLDER, premri_native_bids_fname),
          MRI_bids_fname=os.path.join(BIDS_PRESURG_ANAT_DIR, premri_bids_fname),
    shell:
         # create BIDS session directory and copy file there
         "echo 'acpcdetect -i {input.MRI_bids_fname} -center-AC -output-orient RAS;'"
         "echo {output.MRI_bids_fname};"
         "mkdir -p {params.acpc_fs_dir};"
         "cp {input.MRI_bids_fname} {output.MRI_bids_fname_fscopy};"
         # run acpc auto detection
         "acpcdetect -i {output.MRI_bids_fname_fscopy} -center-AC -output-orient RAS;"
         "cp {output.MRI_bids_fname_fscopy} {output.MRI_bids_fname};"

"""
Rule for coregistering .nifit images -> .nifti for T1 space using Flirt in FSL.

E.g. useful for CT, and DTI images to be coregistered
"""
rule coregistert1_ct_to_t1w:
    input:
         MRI_bids_fname=os.path.join(BIDS_PRESURG_ANAT_DIR, premri_bids_fname),
         CT_bids_fname=os.path.join(BIDS_PRESURG_CT_DIR, ct_native_bids_fname),
    output:
          # mapped image from CT -> MRI
          CT_IN_PRE_NIFTI_IMG_ORIGgz=os.path.join(FSOUT_CT_FOLDER, ctint1_bids_fname + ".gz"),
          CT_IN_PRE_NIFTI_BIDS=os.path.join(BIDS_PRESURG_CT_DIR, ctint1_bids_fname),
          # mapping matrix for post to pre in T1
          MAPPING_FILE_ORIG=os.path.join(FSOUT_CT_FOLDER, pre_to_post_transform_fname),
          MAPPING_FILE_BIDS=os.path.join(BIDS_PRESURG_CT_DIR, pre_to_post_transform_fname),
    shell:
         "flirt -in {input.CT_bids_fname} \
                             -ref {input.MRI_bids_fname} \
                             -omat {output.MAPPING_FILE_ORIG} \
                             -out {output.CT_IN_PRE_NIFTI_IMG_ORIGgz};"
         "mrconvert {output.CT_IN_PRE_NIFTI_IMG_ORIGgz} {output.CT_IN_PRE_NIFTI_BIDS};"
         "cp {output.MAPPING_FILE_ORIG} {output.MAPPING_FILE_BIDS};"

"""
Rule for coregistering .nifit images -> .nifti for T1 space using Flirt in FSL.

E.g. useful for CT, and DTI images to be coregistered
"""
rule coregistert1_ct_to_t1wacpc:
    input:
         MRI_bids_fname=os.path.join(BIDS_PRESURG_ANAT_DIR, premri_bids_fname),
         CT_bids_fname=os.path.join(BIDS_PRESURG_CT_DIR, ct_native_bids_fname),
    output:
          # mapped image from CT -> MRI
          CT_IN_PRE_NIFTI_IMG_ORIGgz=os.path.join(FSOUT_CT_FOLDER, ctint1_acpc_bids_fname + ".gz"),
          CT_IN_PRE_NIFTI_BIDS=os.path.join(BIDS_PRESURG_CT_DIR, ctint1_acpc_bids_fname),
          # mapping matrix for post to pre in T1
          MAPPING_FILE_ORIG=os.path.join(FSOUT_CT_FOLDER, pre_to_post_acpc_transform_fname),
          MAPPING_FILE_BIDS=os.path.join(BIDS_PRESURG_CT_DIR, pre_to_post_acpc_transform_fname),
    shell:
         "flirt -in {input.CT_bids_fname} \
                             -ref {input.MRI_bids_fname} \
                             -omat {output.MAPPING_FILE_ORIG} \
                             -out {output.CT_IN_PRE_NIFTI_IMG_ORIGgz};"
         "mrconvert {output.CT_IN_PRE_NIFTI_IMG_ORIGgz} {output.CT_IN_PRE_NIFTI_BIDS};"
         "cp {output.MAPPING_FILE_ORIG} {output.MAPPING_FILE_BIDS};"

"""
Use mne.coregistration
"""
# rule estimate_fiducials:
#     input:
#
#     output:
#
#     params:
#
#     shell:

"""
Use pydeface.
"""
# rule deface:
