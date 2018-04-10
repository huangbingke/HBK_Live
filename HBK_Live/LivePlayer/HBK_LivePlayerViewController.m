//
//  HBK_LivePlayerViewController.m
//  HBK_Live
//
//  Created by 黄冰珂 on 2018/1/3.
//  Copyright © 2018年 黄冰珂. All rights reserved.
//

#import "HBK_LivePlayerViewController.h"





@interface HBK_LivePlayerViewController ()

@end

@implementation HBK_LivePlayerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}
- (IBAction)back:(UIButton *)sender {
    
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
