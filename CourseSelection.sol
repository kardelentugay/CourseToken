pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

library Infrastructure{
    struct Course {
        bytes32 courseId;
        string courseName;
        uint courseDay;
        uint startingHour;
        uint endingHour;
        uint ects;
        uint semestre;
        bool isMust;
        uint grade;
        bool succeeded;
        bool isResigend;
        bool isActive;
    }
    
    struct Student{
        address studentAddress;
        string studentId;
        string studentName;
        uint agno;
        uint semestre;
        uint coursesCount;
        uint resignedCoursesCount;
    }
    
    function checkOverlaps(Course memory c1, Course memory c2) public returns(bool){
        if(c1.courseDay == c2.courseDay){
            if((c1.startingHour == c2.startingHour || c1.endingHour == c2.endingHour) ||
            (c1.startingHour > c2.startingHour && c1.startingHour < c2.endingHour) ||
            (c1.endingHour > c2.startingHour && c1.endingHour < c2.endingHour) ||
            (c2.startingHour > c1.startingHour && c2.startingHour < c1.endingHour) ||
            (c2.endingHour > c1.startingHour && c2.endingHour < c1.endingHour)){
                return true;
            }
        }
        else return false;
    }
}

contract CourseToken is ERC20, Ownable {
    address ownerAddress;
    
    mapping(address => bool) public whitelist;
    mapping(address=>Infrastructure.Student) public students;
    mapping(address=>Infrastructure.Course[]) public coursesOfStudent;
    mapping(address=>mapping(bytes32=>bool)) public activeCoursesOfStudentMap;
    mapping(address=>mapping(bytes32=>bool)) public succeededCoursesOfStudentMap;
    mapping(address=>uint) public activeCoursesCountOfStudent;
    
    //storage about courses
    mapping(bytes32=>Infrastructure.Course) public courses;
    mapping(bytes32=>bool) public addedCourses;

    event CRSMinted(bool indexed minted);
    event CRSBurned(bool indexed burned);
    event AllowanceGiven(bool indexed allowed);
    event StudentCreated(bool indexed created);
    event CourseCreated(bool indexed created);
    event BalanceSent(bool indexed sent);
    event Resigned(bool indexed resigned);
    event CourseSelected(bool indexed selected);
    event CourseAssigned(bool indexed assigned);
    event GradeSet(bool indexed set);
    event AgnoAndSemestreSet(bool indexed set);
    
    constructor() ERC20("Course Token", "CRS") {
        _mint(msg.sender, 1000000);
        ownerAddress = msg.sender;
    }
    
    modifier onlyWhitelisted() {
        require(isWhitelisted(msg.sender));
        _;
    }
    
    function isWhitelisted(address _address) public view returns (bool) {
        return whitelist[_address];
    }
    
    function mintCRSInternal(address receiver, uint256 _amount) internal{
        _mint(receiver, _amount);
        emit CRSMinted(true);
    }
    
    function mintCRS() public onlyOwner returns (bool success)
    {
        _mint(msg.sender, 1000);
        emit CRSMinted(true);
        return true;
    }
    
    function burnCRS() public onlyOwner returns (bool success)
    {
        require(balanceOf(msg.sender) > 1000, "Address must own more than 1000 CRS Tokens");
        _burn(msg.sender, 1000);
        emit CRSBurned(true);
        return true;
    }
    
    function giveAllowance(uint256 _amount) public onlyWhitelisted returns(bool){
        approve(ownerAddress, _amount);
        emit AllowanceGiven(true);
        return true;
    }
    
    function sendBalance(address _studentAddress, uint _amount) public onlyOwner returns(bool){
        require(balanceOf(msg.sender)>_amount, "Not enough balance, please mint some tokens");
        transfer(_studentAddress, _amount);
        emit BalanceSent(true);
    }
    
    function createCourse(string memory _courseCode, string memory _courseName, uint _day,
    uint _startingHour, uint _endingHour, uint _ects, uint _semestre, bool _isMust) public onlyOwner returns(bool){
        bytes32 courseId = keccak256(abi.encodePacked(_courseCode));
        
        require(addedCourses[courseId] == false, "Course already exists");
        require(_day<8 && _day>0, "Day number must be between 1 and 7");
        require(_startingHour<_endingHour,"Ending hour cannot be earlier than starting hour");
        require(_startingHour<24, "Starting hour must be earlier than 24");
        require(_endingHour<24, "Ending hour must be earlier than 24");
        
        Infrastructure.Course memory course = Infrastructure.Course(courseId, _courseName, _day, _startingHour, 
                                                _endingHour, _ects, _semestre, _isMust, 0, false, false, false);
        
        courses[courseId] = course;
        addedCourses[courseId] = true;
        
        emit CourseCreated(true);
        return true;
    }
    
    function retrieveCourseInfo(string memory _courseCode) public view onlyWhitelisted returns(Infrastructure.Course memory){
        return(courses[keccak256(abi.encodePacked(_courseCode))]);
    }
    
    function assignCourse(address _studentAddress, string memory _courseCode) public onlyOwner returns(bool){
        require(_studentAddress != address(0), "Student address should exist");
        require(whitelist[_studentAddress]==true, "Record not found, please add student first");
        
        //get the course with basic info
        bytes32 courseId = keccak256(abi.encodePacked(_courseCode));
        
        require(allowance(_studentAddress, msg.sender)>=courses[courseId].ects,"Student must approve to superviser with enough credit");
        require(balanceOf(_studentAddress)>=courses[courseId].ects, "Student balance is not enought to get this course");
        
        require(addedCourses[courseId]==true,"Please add the course first");
        require(activeCoursesOfStudentMap[_studentAddress][courseId] == false, "Course is already assigned to the student");
        
        Infrastructure.Course memory course = courses[courseId];
        course.isActive = true;
        
        coursesOfStudent[_studentAddress].push(course);
        students[_studentAddress].coursesCount += 1;
        activeCoursesCountOfStudent[_studentAddress]++;
        activeCoursesOfStudentMap[_studentAddress][courseId] = true;
        
        transferFrom(_studentAddress, ownerAddress, courses[courseId].ects);
        emit CourseAssigned(true);
        
        return true;
    }
    
    function retrieveActiveCourseOfStudent(address _studentAddress, string memory _courseCode) public view onlyWhitelisted returns(bool){
        bytes32 courseId = keccak256(abi.encodePacked(_courseCode));
        return activeCoursesOfStudentMap[_studentAddress][courseId];
    }
    
    function getCourse(string memory _courseCode) external onlyWhitelisted returns(bool){
        bytes32 courseId = keccak256(abi.encodePacked(_courseCode));
        require(addedCourses[courseId]==true,"Please add the course first");
        
        require(courses[courseId].ects <= balanceOf(msg.sender),"Not enough balance to select this course");
        
        if(students[msg.sender].semestre < courses[courseId].semestre){
            require(students[msg.sender].agno>=50, "AGNO is not eligable");
        }
        require(activeCoursesOfStudentMap[msg.sender][courseId] == false, "Course is already assigned to the student");
        
        for(uint i = 0; i< students[msg.sender].coursesCount; i++){
            //check if course hours overlapping
            if(coursesOfStudent[msg.sender][i].isActive == true && 
            Infrastructure.checkOverlaps(coursesOfStudent[msg.sender][i], courses[courseId]) == true){
                revert("Courses are overlapping");
            }
            
            if(coursesOfStudent[msg.sender][i].courseId != courseId &&
            coursesOfStudent[msg.sender][i].semestre<students[msg.sender].semestre &&
            coursesOfStudent[msg.sender][i].isMust == true && 
            coursesOfStudent[msg.sender][i].succeeded == false &&
            coursesOfStudent[msg.sender][i].isActive == false){
                revert("You should take failed must courses first");
            }
            
            //check if student takes previous course
            if(coursesOfStudent[msg.sender][i].courseId == courseId &&
            coursesOfStudent[msg.sender][i].semestre <= students[msg.sender].semestre){
                coursesOfStudent[msg.sender][i].grade = 0;
                coursesOfStudent[msg.sender][i].succeeded = false;
                coursesOfStudent[msg.sender][i].isResigend = false;
                coursesOfStudent[msg.sender][i].isActive = true;
                activeCoursesCountOfStudent[msg.sender]++;
                activeCoursesOfStudentMap[msg.sender][courseId] = true;
                
                transfer(ownerAddress, courses[courseId].ects);
                
                emit CourseSelected(true);
                return true;
            }
            
        }
        
        
        Infrastructure.Course memory course = courses[courseId];
        course.isActive = true;
    
        //require(msg.sender.balance>course.ects,"Not enough balance!");
        
        coursesOfStudent[msg.sender].push(course);
        students[msg.sender].coursesCount++;
        activeCoursesCountOfStudent[msg.sender]++;
        activeCoursesOfStudentMap[msg.sender][courseId] = true;
        
        transfer(ownerAddress, courses[courseId].ects);
        
        emit CourseSelected(true);
        return true;
    }
    
    function resignOnbehalfOf(address _studentAddress, string memory _courseCode) public onlyOwner returns(bool){
        require(students[_studentAddress].resignedCoursesCount < 4, "Resigned courses limit is over");
        bytes32 courseId = keccak256(abi.encodePacked(_courseCode));
        require(addedCourses[courseId]==true,"Please add the course first");
        
        for(uint i=0; i<students[_studentAddress].coursesCount; i++){
            if(coursesOfStudent[_studentAddress][i].courseId == courseId && coursesOfStudent[_studentAddress][i].isActive){
                coursesOfStudent[_studentAddress][i].isResigend = true;
                coursesOfStudent[_studentAddress][i].isActive = false;
                students[_studentAddress].resignedCoursesCount++;
                activeCoursesCountOfStudent[_studentAddress]--;
                activeCoursesOfStudentMap[_studentAddress][courseId] = false;
                
                mintCRSInternal(_studentAddress, courses[courseId].ects);
                
                emit Resigned(true);
                return true;
            }
        }
        
        revert("Course not found or inactive");
        
        return false;
    }
    
    function resignCourse(string memory _courseCode) public onlyWhitelisted returns(bool){
        require(students[msg.sender].resignedCoursesCount < 4, "Resigned courses limit is over");
        if(students[msg.sender].semestre == 1){
            revert("You cannot resign any courses in the first semestre");
        }
        //require(students[msg.sender].semestre == 1, "You cannot resign any courses in the first semestre");
        require(activeCoursesCountOfStudent[msg.sender]>1, "You have only 1 active course, cannot resign");
        
        bytes32 courseId = keccak256(abi.encodePacked(_courseCode));
        require(addedCourses[courseId]==true,"Please add the course first");
        
        for(uint i=0; i<students[msg.sender].coursesCount; i++){
            if(coursesOfStudent[msg.sender][i].courseId == courseId && coursesOfStudent[msg.sender][i].isActive){
                coursesOfStudent[msg.sender][i].isResigend = true;
                coursesOfStudent[msg.sender][i].isActive = false;
                students[msg.sender].resignedCoursesCount++;
                activeCoursesCountOfStudent[msg.sender]--;
                activeCoursesOfStudentMap[msg.sender][courseId] = false;
                
                mintCRSInternal(msg.sender ,coursesOfStudent[msg.sender][i].ects);
                
                emit Resigned(true);
                return true;
            }
        }
        
        revert("Course not found or inactive");
    }
    
    
    function setCourseGrade(address _studentAddress, string memory _courseCode, uint _grade) public onlyOwner returns(bool){
        require(_grade<=100,"Grade cannot be higher than 100");
        bytes32 courseId = keccak256(abi.encodePacked(_courseCode));
        
        require(addedCourses[courseId]==true,"Please add the course first");
        
        for(uint i=0; i<students[_studentAddress].coursesCount; i++){
            if(coursesOfStudent[_studentAddress][i].courseId == courseId && coursesOfStudent[_studentAddress][i].isActive == true){
                coursesOfStudent[_studentAddress][i].grade = _grade;
                if(_grade>39){
                    coursesOfStudent[_studentAddress][i].succeeded = true;
                    succeededCoursesOfStudentMap[_studentAddress][courseId] = true;
                }
                coursesOfStudent[_studentAddress][i].isActive = false;
                succeededCoursesOfStudentMap[_studentAddress][courseId] = false;
                activeCoursesCountOfStudent[_studentAddress]--;
                activeCoursesOfStudentMap[_studentAddress][courseId] = false;
                
                emit GradeSet(true);
                return true;
            }
        }
        revert("Course not found or inactive");
    }
    
    //functions about student
    function createStudent(address _studentAddress, string memory _studentId, string memory _studentName,
    uint _agno, uint _semestre)
        public
        onlyOwner
        returns (bool success)
    {
        require(_studentAddress != address(0), "Student address should exist");
        
        require(whitelist[_studentAddress]==false, "student already exists");
        require(_agno<101, "AGNO cannot be higher than 100");
        require(_semestre<9, "Semestre cannot be higher than 8");
        
        students[_studentAddress] = Infrastructure.Student(_studentAddress, _studentId, _studentName, _agno, _semestre, 0, 0);
        
        whitelist[_studentAddress] = true;
        _mint(_studentAddress, 25);
        
        emit StudentCreated(true);

        return true;
    }
    
    function setAgnoAndSemestre(address _studentAddress, uint _agno, uint _semestre) public onlyOwner returns(bool){
        require(whitelist[_studentAddress] == true, "Student not found");
        require(_agno<=100, "AGNO cannot be higher than 100");
        require(_semestre>0 && _semestre<9, "Semetre should be between 1 and 8");
        students[_studentAddress].semestre = _semestre;
        students[_studentAddress].agno = _agno;
        
        emit AgnoAndSemestreSet(true);
        
        return true;
    }
}


