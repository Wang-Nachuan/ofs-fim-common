#!/usr/bin/env python

# Copyright 2020 Intel Corporation
# SPDX-License-Identifier: MIT

import argparse
import collections
import configparser
import logging
import logging.handlers
import os
import sys


def print_ip_config(configuration):
    """
    Output all OFSS configurations
    """
    for section, section_values in configuration.items():
        logging.info(f"\t{section}:")
        for param, value in section_values.items():
            logging.info(f"\t\t{param} : {value}")


def process_input_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--ofss",
        "--ini",
        dest="ofss",
        nargs="+",
        required=True,
        help="Input OFSS config file",
    )

    return parser.parse_args()


def process_config_sections(ofss_config):
    """
    Parse each section of OFSS file for IP pertinent info
    """
    curr_ip_config = {}
    for section in ofss_config:
        if section not in ["DEFAULT", "default", "ip", "include"]:
            curr_ip_config[section] = dict(ofss_config.items(section))

    return curr_ip_config


def note_config_defaults(ofss_config_files_queue, ofss_config):
    """
    Gather all default OFSS files. Default files will be used if no OFSS file for
    a default configuration is passed on the command line.
    """
    # For backward compatibility, "include" is a synonym for "default".
    for section in ["default", "include"]:
        if section in ofss_config:
            for elem in ofss_config[section]:
                info = {'name': os.path.expandvars(elem).replace('"', ""),
                        'default': 1}
                ofss_config_files_queue.append(info)


def check_ofs_config(ofs_config):
    """
    Check that all pertinent info for the design is provided. 
    These parameters are necessary for subsequent actions executed by OFSS Config tool
    """
    required_info = ["platform", "family", "part", "device_id"]
    for elem in required_info:
        if elem not in ofs_config.keys():
            logging.info(f"{elem} not found for currenty OFS configuration")
            sys.exit(1)

    if ofs_config["family"].lower() != "agilex":
        logging.info(f"OFSS Config tool currently only supporting Agilex")
        sys.exit(1)


def output_name_unique(new_config, ip_configs):
    """
    Return True if the output name of new_config is not already present in
    the ip_configs list of configurations.
    """
    new_name = None
    if "settings" in new_config and "output_name" in new_config["settings"]:
        new_name = new_config["settings"]["output_name"]

    if not new_name:
        # new_config doesn't have a name. Probably an OFSS error. Claim it
        # is a unique name.
        return True

    for ip in ip_configs:
        if "settings" in ip and "output_name" in ip["settings"]:
            old_name = ip["settings"]["output_name"]

        if new_name == old_name:
            return False

    return True


def check_num_ip_configs(new_config, new_config_fname, ip_configs):
    """
    Check there isn't more than 1 configuration setting for each IP.
    """
    if not ip_configs:
        return

    if not output_name_unique(new_config, ip_configs):
        logging.info(f"!!Error!! {new_config_fname} is a duplicate IP configuration")
        logging.info("Previous configurations:")
        for ip_c in ip_configs:
            logging.info(f"{ip_c}")
        sys.exit(1)

def check_configurations(ofs_ip_configurations):
    """
    Check that overall OFS setting is provided
    """
    if "ofs" not in ofs_ip_configurations:
        logging.info("!!Error!! Must have OFS project info. No base file included.")
        sys.exit(1)

    check_ofs_config(ofs_ip_configurations["ofs"][0]["settings"])

def process_ofss_configs(ofss_list):
    """
    Breadth First Search for including and parsing all OFSS files.
    OFSS files can be passed in as individual files on the cmd line, or
    as files under the [default] section.
    All OFSS configurations are stored in one dictionary structure
    """

    # Queue of file names to process. Each entry in the queue is a
    # dictionary with two entries:
    #  - name: full path of the file to load
    #  - default: 1 if to file is a default to be used only if a
    #             specific setting is not already loaded.
    ofss_config_files_queue = collections.deque()

    for ofss_string in ofss_list:
        ofss_elems = ofss_string.split(",")
        for ofss in ofss_elems:
            if ofss:
                ofss_abs_path = os.path.abspath(ofss)
                ofss_config_files_queue.append({'name': ofss_abs_path,
                                                'default': 0})

    ofs_ip_configurations = collections.defaultdict(list)
    already_processed_configs = set()
    while ofss_config_files_queue:
        curr_config = configparser.ConfigParser(allow_no_value=True)
        curr_config.optionxform = str

        curr_ofss_file_info = ofss_config_files_queue.popleft()
        curr_ofss_file = curr_ofss_file_info['name']
        logging.debug(f"Processing {curr_ofss_file} {curr_ofss_file_info['default']}")

        if not os.path.exists(curr_ofss_file):
            raise FileNotFoundError(f"{curr_ofss_file} not found")

        if curr_ofss_file in already_processed_configs:
            continue

        ip_type = None
        curr_config.read(curr_ofss_file)
        if "ip" in curr_config:
            ip_type = curr_config["ip"]["type"].lower()

        note_config_defaults(ofss_config_files_queue, curr_config)
        if ip_type is not None:
            # Default files are always pushed to the end of the file queue.
            # If the user specifies an IP config file on the command line
            # it will be seen before any default option.
            if curr_ofss_file_info['default'] and \
               ip_type in ofs_ip_configurations and \
               not output_name_unique(curr_config, ofs_ip_configurations[ip_type]):
                # Ignore default when an instance of ip_type was already
                # processed.
                logging.debug(f"Ignoring default {ip_type}: {curr_ofss_file}")
            else:
                if not curr_ofss_file_info['default']:
                    logging.info(f"Applying {ip_type}: {curr_ofss_file}")
                else:
                    logging.info(f"Applying default {ip_type}: {curr_ofss_file}")

                check_num_ip_configs(curr_config, curr_ofss_file,
                                     ofs_ip_configurations[ip_type])
                ofs_ip_configurations[ip_type].append(process_config_sections(curr_config))

        already_processed_configs.add(curr_ofss_file)

    check_configurations(ofs_ip_configurations)

    return ofs_ip_configurations


def main():
    args = process_input_arguments()
    ofs_ip_configurations = process_ofss_configs(args.ofss)

    for ip, ip_configurations in ofs_ip_configurations.items():
        for ip_config in ip_configurations:
            print_ip_config(ip_config)


if __name__ == "__main__":
    main()
