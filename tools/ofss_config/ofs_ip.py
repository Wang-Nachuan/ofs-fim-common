#!/usr/bin/env python

# Copyright 2020 Intel Corporation
# SPDX-License-Identifier: MIT

import logging
import logging.handlers
import os
import re
import shutil
import subprocess
import sys


class OFS:
    """
    Base class to be inherited by all IPs. 
    Contains common methods and attributes to be configured and called.
    """
    def __init__(self, ofs_config, target):
        """
        Constructor containing info on the OFS design and corresponding IP
        """
        self.ofs_config = ofs_config
        self.platform = ""
        self.fpga_family = ""
        self.fim = ""
        self.part = ""
        self.device_id = ""
        self.p_clk = ""
        self.set_target_rootdir(target)
        self.get_project_settings()


        self.ip_type = ""
        self.ip_component = ""
        self.ip_output_name = ""
        self.ip_instance_name = ""
        self.ip_path = ""
        self.ip_output_base = ""
        self.ip_file = ""
        self.ip_preset = ""

        self.ip_component_params = {}
        self.artifacts_to_clean = []

    def _check_config_enable(self, config_param_value):
        """
        For OFSS 'enable' parameters, equate both boolean and 0/1 values.
        """
        return config_param_value == "True" or config_param_value == "1"

    def _errorExit(self, msg):
        """
        Common exit method to alert user of problem.
        Abort if violation
        """
        print(f"!!FAIL!! {msg}", file=sys.stdout)
        sys.exit(1)

    def set_target_rootdir(self, target):
        """
        Configure IPs according to optional 'target' work directory
        """
        if target:
            # Target root directory is specified
            self.target_rootdir = target
        else:
            # Default to OFS_ROOTDIR
            try:
                self.target_rootdir = os.environ["OFS_ROOTDIR"]
            except KeyError:
                self._errorExit("$OFS_ROOTDIR environment variable is not defined!")

        # Does the target exist
        if not os.path.isdir(self.target_rootdir):
            self._errorExit(
                f'Target root "{self.target_rootdir}" does not exist or is not a directory!'
            )

    def get_project_settings(self):
        """
        Get OFS settings from configuration dictionary
        """
        self.platform = self.ofs_config["settings"]["platform"]
        self.fim = self.ofs_config["settings"]["fim"]
        self.fpga_family = self.ofs_config["settings"]["family"]
        self.part = self.ofs_config["settings"]["part"]
        self.device_id = self.ofs_config["settings"]["device_id"]

        # If IOPLL OFSS is provided for p_clk configuration, update OFS setting's p_clk parameter
        # p_clk parameter will need to be visible for subsequent IP configuration (ex: PCIe)
        if "p_clk" in self.ofs_config["settings"]:
            self.p_clk = self.ofs_config["settings"]["p_clk"]

    def get_quartus_search_string_arg(self):
        """
        Provide path to quartus
        """
        return f'--search-path="{self.get_quartus_search_string()}"'

    def get_quartus_search_string(self):
        return "$OFS_ROOTDIR/ipss/**/*,$"
        
    def set_ip_deploy_args(self):
        """
        Set up all the IP specific parameters for IP Deploy Command
        """
        ip_args = []
        if self.ip_output_name:
            ip_args.append(f'--output-name="{self.ip_output_name}"')
        if self.ip_component:
            ip_args.append(f'--component-name="{self.ip_component}"')
        if self.ip_instance_name:
            ip_args.append(f'--instance-name="{self.ip_instance_name}"')
        if self.ip_path:
            ip_args.append(f"--output-directory={self.ip_path}")
        if self.ip_preset:
            ip_args.append(f'--preset="{self.ip_preset}"')

        for param, value in self.ip_component_params.items():
            ip_args.append(f'--component-parameter={param}="{value}"')

        return ip_args

    def set_deploy_cmd_args(self):
        """
        Set up IP Deploy command
        """
        deploy_args = ["ip-deploy"]
        deploy_args.append(f"--family={self.fpga_family}")
        deploy_args.append(f'--part="{self.part}"')
        deploy_args.append(self.get_quartus_search_string_arg())

        ip_args = self.set_ip_deploy_args()
        deploy_args.extend(ip_args)

        return deploy_args

    def deploy(self):
        """
        Execute IP Deploy command.
        """
        self.clean()

        if not self.ip_preset or self.ip_component_params:
            # Normal case: not using a preset or there are IP component
            # parameters specified. Use ip-deploy.
            cmd = self.get_deploy_cmd()
        else:
            # Memory subsystems with presets can be generated much
            # faster using qsys-script. This will likely be fixed after
            # Quartus 24.1.
            cmd = self.get_qsys_script_cmd()

        # Drop PD debug messages, e.g. "2024.05.24.16:39:01 [Debug] <text>"
        debug_msg_pattern = re.compile(r".*:[0-9]+ \[Debug\] .*")

        p = subprocess.Popen(cmd, stdout=subprocess.PIPE, shell=True) # nosec
        for line in p.stdout:
            line = line.decode().rstrip()
            if not debug_msg_pattern.match(line):
                print(line, flush=True)

        deploy_status = p.wait()
        if deploy_status != 0:
            raise self._errorExit("IP Deploy Failed!!")

        logging.info("=========================")
        logging.info(f"IP-Deploy for {self.ip_component} COMPLETED")
        logging.info("=========================")

    def dump_ip_deploy_cmd(self):
        """
        Log all IP deploy commands to 'ip_deploy_cmds.log' file 
        Use in conjunction with `--debug` flag at command line
        """
        msg = []
        msg.append("")
        msg.append("*********************************************")
        msg.append(f"{self.ip_type} IP Deploy Command:")
        msg.append("*********************************************")
        msg.extend(self.set_deploy_cmd_args())
        msg.append("=============================================")

        msg_string = "\n".join(msg)
        with open("ip_deploy_cmds.log", "a+") as fOut:
            fOut.write(msg_string)

    def get_deploy_cmd(self):
        """
        Fetch the IP Deploy Command
        """
        deploy_args = self.set_deploy_cmd_args()
        deploy_cmd = " ".join(deploy_args)

        logging.info("Deploy Command:")
        logging.info(f"{deploy_cmd}")

        return deploy_cmd

    def set_qsys_script_args(self):
        """
        Set up qsys-script command. Results are equivalent to ip-deploy but
        the script runs faster in some cases.

        The arguments generated here work only with presets. The procedure
        could be extended to handle all IP generation, but there is no
        reason to do so.
        """
        qsys_args = ["qsys-script"]
        qsys_args.append("--qpf=none")
        qsys_args.append(self.get_quartus_search_string_arg())

        if self.ip_path:
            output_file = os.path.join(self.ip_path, self.ip_output_name)
        else:
            output_file = self.ip_output_name

        # Tcl commands passed to --cmd argument
        cmd = ["package require qsys"]
        cmd.append(f"set_project_property DEVICE {{{self.part}}}")
        cmd.append(f"set_project_property DEVICE_FAMILY {{{self.fpga_family}}}")
        cmd.append("set_project_property BOARD {default}")
        cmd.append("set_validation_property AUTOMATIC_VALIDATION false")
        instance_name = self.ip_instance_name
        if not instance_name:
            instance_name = self.ip_output_name
        cmd.append(f"add_component {instance_name} {output_file}.ip " +
                   f"{self.ip_component} {instance_name}")
        cmd.append(f"load_component {instance_name}")
        cmd.append(f"apply_component_preset {{{self.ip_preset}}}")
        cmd.append("save_component")

        qsys_args.append(f"--cmd=\"{'; '.join(cmd)}\"")

        return qsys_args

    def get_qsys_script_cmd(self):
        """
        Fetch qsys-script command
        """
        deploy_args = self.set_qsys_script_args()
        deploy_cmd = " ".join(deploy_args)

        logging.info("Deploy Command:")
        logging.info(f"{deploy_cmd}")

        return deploy_cmd

    def get_qsys_gen_command(self):
        """
        Fetch qsys_gen command
        """
        lines = []
        lines.append("\n\n# This would generate the IP RTL. It is here as an example.")
        lines.append("# Quartus will generate the RTL during the FIM build.")
        lines.append(
            f"# qsys-generate {self.ip_file} --output-directory={self.ip_path}/ "
            f"--pro --simulation --simulator=MODELSIM --simulator=VCS --simulator=VCSMX --clear-output-directory \\\n"
            f"#  --search-path={self.get_quartus_search_string()}"
        )
        return "\n".join(lines)

    def clean(self):
        """
        Delete existing IP file and its generated tree before producing
        the new one. This is particularly important in work trees where
        we want to update the work copy and not a link to the source
        repository.
        """
        logging.info(f"Going to clean the following: {self.artifacts_to_clean}")
        for elem in self.artifacts_to_clean:
            if os.path.exists(elem):
                if os.path.isdir(elem):
                    shutil.rmtree(elem)
                else:
                    os.remove(elem)

    def summarize_configuration(self):
        """
        OFS Configuration Summary
        """
        logging.info("")
        logging.info("=========================")
        logging.info("OFS OFSS Configuration Summary")
        logging.info("=========================")
