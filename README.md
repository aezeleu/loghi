# Loghi

Loghi is a set of tools for Handwritten Text Recognition. 

Two sample scripts are provided to make starting everything a little bit easier. 
na-pipeline.sh: for transcribing scans
na-pipeline-train.sh: for training new models. 

## Quick start

Install Loghi so that you can use its pipeline script.
```bash
git clone git@github.com:knaw-huc/loghi.git
cd loghi
```

## Use the docker images
The easiest method to run Loghi is to use the default dockers images on [Docker Hub](https://hub.docker.com/u/loghi).
The docker images are usually pulled automatically when running [`na-pipeline.sh`](na-pipeline.sh) mentioned later in this document, but you can pull them separately with the following commands:

```bash
docker pull loghi/docker.laypa
docker pull loghi/docker.htr
docker pull loghi/docker.loghi-tooling
```

If you do not have Docker installed follow [these instructions](https://docs.docker.com/engine/install/) to install it on your local machine.

If you instead want to build the dockers yourself with the latest code:
```bash
git submodule update --init --recursive
cd docker
./buildAll.sh
```
This also allows you to have a look at the source code inside the dockers. The source code is available in the submodules.


## Inference

But first go to:
https://surfdrive.surf.nl/files/index.php/s/YA8HJuukIUKznSP
and download a laypa model (for detection of baselines) and a loghi-htr model (for HTR).

suggestion for laypa:
- general

suggestion for loghi-htr that should give some results:
- generic-2023-02-15

It is not perfect, but a good starting point. It should work ok on 17th and 18th century handwritten dutch. For best results always finetune on your own specific data.

edit the [`na-pipeline.sh`](na-pipeline.sh) using vi, nano, other whatever editor you prefer. We'll use nano in this example

```bash
nano na-pipeline.sh
```
Look for the following lines:
```
LAYPAMODEL=INSERT_FULL_PATH_TO_YAML_HERE
LAYPAMODELWEIGHTS=INSERT_FULLPATH_TO_PTH_HERE
HTRLOGHIMODEL=INSERT_FULL_PATH_TO_LOGHI_HTR_MODEL_HERE
```
and update those paths with the location of the files you just downloaded. If you downloaded a zip: you should unzip it first.

if you do not have a NVIDIA-GPU and nvidia-docker setup additionally change

```text
GPU=0
```
to
```text
GPU=-1
```
It will then run on CPU, which will be very slow. If you are using the pretrained model and run on CPU: please make sure to download the Loghi-htr model starting with "float32-". This will run faster on CPU than the default mixed_float16 models.


Save the file and run it:
```bash
./na-pipeline.sh /PATH_TO_FOLDER_CONTAINING_IMAGES
```
replace /PATH_TO_FOLDER_CONTAINING_IMAGES with a valid directory containing images (.jpg is preferred/tested) directly below it.

The file should run for a short while if you have a good nvidia GPU and nvidia-docker setup. It might be a long while if you just have CPU available. It should work either way, just a lot slower on CPU.

When it finishes without errors a new folder called "page" should be created in the directory with the images. This contains the PageXML output.

## Training an HTR model

### Input data

Expected structure
```text
training_data_folder
|- training_all_train.txt
|- training_all_val.txt
|- image1_snippets
    |-snippet1.png
    |-snippet2.png
```

`training_all_train.txt` should look something something like:
```text
/path/to/training_data_folder/image1_snippets/snippet1.png	textual representation of snippet 1
/path/to/training_data_folder/image1_snippets//snippet2.png text on snippet 2
```
n.b. path to image and textual representation should be separated by a tab.

##### Create training data
You can create training data with the following command:
```bash
./create_train_data.sh /full/path/to/input /full/path/to/output
```
`/full/path/to/output` is `/full/path/to/training_data_folder` in this example
`/full/path/to/input` is expected to look like:
```text
input
|- image1.png
|- image2.png
|- page
    |- image1.xml
    |- image2.xml
```
`page/image1.xml` should contain information about the baselines and should have the textual representation of the text lines.  

### Change script
Edit the [`na-pipeline-train.sh`](na-pipeline-train.sh) script using your favorite editor:

```bash
nano na-pipeline-train.sh
```

Find the following lines:
```text
listdir=INSERT_FULL_PATH_TO_TRAINING_DATA_FOLDER
trainlist=INSERT_FULL_PATH_TO_TRAINING_DATA_LIST
validationlist=INSERT_FULL_PATH_TO_VALIDATION_DATA_LIST
```
In this example: 
```text
listdir=/full/path/to/training_data_folder
trainlist=/full/path/to/training_data_folder/train_list.txt
validationlist=/full/path/to/training_data_folder/val_list.txt
```

if you do not have a NVIDIA-GPU and nvidia-docker setup additionally change:

```text
GPU=0
```
to
```text
GPU=-1
```
It will then run on CPU, which will be very slow.


### Run script
Finally, to run the HTR training run the script:

```bash
./na-pipeline-train.sh
```

## Updated Usage for `na-pipeline.sh`

The `na-pipeline.sh` script has been updated to accept two mandatory arguments:

1. **Path to images**: The directory containing images to be processed for Handwritten Text Recognition (HTR).
2. **Path to result directory**: The directory where the results, including the "page" folder with baselines and XML files, will be copied after processing.

### Example Usage

To run the script, use the following command:

```bash
./na-pipeline.sh /path/to/images /path/to/result-directory
```

### Changes in `na-pipeline.sh`

- **Second Argument**: A new argument has been added to specify the directory where the "page" folder (containing baselines and XML files) will be moved after processing.
- **Validation**: The script now includes validation to ensure the result directory is specified and accessible.
- **Testing**: The script has been successfully tested on WSL2 using the Ubuntu distribution.

### Running on Windows with Docker

To run the `na-pipeline.sh` script on Windows, you can use Windows Subsystem for Linux (WSL) or WSL2. Below are the steps to set it up:

1. **What is WSL/WSL2?**
   - WSL (Windows Subsystem for Linux) and WSL2 are compatibility layers for running Linux binary executables natively on Windows 10 and Windows 11. WSL2 offers improved performance and full system call compatibility.

2. **Installing Ubuntu on WSL/WSL2**
   - Follow the [official Microsoft guide](https://docs.microsoft.com/en-us/windows/wsl/install) to install WSL and set up an Ubuntu distribution.

3. **Setting Up Loghi**
   - Extract the Loghi project directory into the WSL file system.
   - Navigate to the project directory in your WSL terminal.

4. **Running the Script**
   - Execute the `na-pipeline.sh` script as a bash script. For example:
     ```bash
     ./na-pipeline.sh ./test ./test-result
     ```

For more detailed instructions and additional information, please refer to the main documentation on the [GitHub repository](https://github.com/knaw-huc/loghi).


## For later updates use:
To update the submodules to the head of their branch (the latest/possibly unstable version) run the following command:
```bash
git submodule update --recursive --remote
```

## Batch Processing with workspace_na_pipeline.sh

For processing multiple directories of images at once, you can use the `workspace_na_pipeline.sh` script. This script automates the HTR processing of multiple subdirectories and organizes the results in a specified output location.

### Usage

```bash
./workspace_na_pipeline.sh <INPUT_DIR> <OUTPUT_DIR>
```

Where:
- `INPUT_DIR`: Parent directory containing subdirectories with images to process
- `OUTPUT_DIR`: Directory where all results will be stored

### Example Structure

Input structure:
```
input_directory/
├── batch1/
│   ├── image1.jpg
│   ├── image2.jpg
├── batch2/
│   ├── image3.jpg
│   └── image4.jpg
```

After processing, the output structure will be:
```
output_directory/
├── batch1_page/
│   ├── image1.xml
│   ├── image2.xml
├── batch2_page/
│   ├── image3.xml
│   └── image4.xml
```

### Example Usage

```bash
./workspace_na_pipeline.sh /path/to/input_directory /path/to/output_directory
```

The script will:
1. Process each subdirectory in the input directory
2. Run the HTR pipeline on each subdirectory's images
3. Move the resulting page files to the output directory
4. Organize results by adding the subdirectory name as a prefix


## XML to Text Conversion

The repository includes a utility script `xml2text.sh` for converting PageXML files to plain text. This script extracts text content from PageXML files generated by the HTR pipeline.

### Usage of xml2text.sh

```bash
./xml2text.sh <INPUT_DIR> <OUTPUT_DIR>
```

Where:
- `INPUT_DIR`: Directory containing PageXML files to convert
- `OUTPUT_DIR`: Directory where the resulting text files will be stored

### Example Usage

```bash
./xml2text.sh ./page_results ./text_output
```

The script will:
1. Process all XML files in the input directory
2. Extract text content from TextLine elements
3. Create corresponding .txt files in the output directory
4. Preserve the reading order of the text

### Output Structure

For each input XML file, the script creates a corresponding text file:
```
input_directory/
├── document1.xml
├── document2.xml

output_directory/
├── document1.txt
├── document2.txt
```

### Workspace Pipeline Details

The `workspace_na_pipeline.sh` script uses a temporary workspace directory (`temp_workspace`) in the current working directory for processing. This workspace:

- Serves as an intermediate processing area
- Handles files with spaces in names by sanitizing directory names
- Preserves original input files
- Automatically cleans up after processing

The workflow is:
1. Creates temporary workspace
2. Copies input files to workspace
3. Processes files in workspace
4. Copies results to output directory
5. Maintains original directory structure in output

### XML to Text Conversion Details

The `xml2text.sh` script uses xmlstarlet to process PageXML files. Important features:

- Preserves reading order of text lines
- Uses PAGE XML 2013-07-15 namespace
- Extracts text from TextEquiv/Unicode elements
- Maintains line breaks between text lines
- Requires xmlstarlet to be installed

Dependencies:

```bash
sudo apt-get install xmlstarlet
```

