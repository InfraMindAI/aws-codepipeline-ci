# AWS CodePipeline-based CI solution for projects, hosted anywhere

AWS CodePipeline source action is typically used to download source code, which is used in its build action. It is convenient, available out-of-the-box and supports a variety of different code repositories. Terraform code here allows to create a pipeline for almost any source code repository or storage, which is not supported by AWS CodePipeline source action yet. We are using the example of SVN pipelines to show how to build a working solution for real-life usage with automatic creation/starting and deletion of pipelines, which are triggered by SVN create branch/commit and delete branch operations.

Read more about it [here](https://workingwiththecloud.com/blog/svn-pipelines/).

Below is the architecture diagram of the solution:
![image](https://github.com/user-attachments/assets/509dafe8-0050-448d-b4d2-b25800e417fa)
